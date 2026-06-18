import 'dart:async';
import 'dart:math' show cos, pi;

import 'package:apptest/features/memory/domain/models/memory_model.dart';
import 'package:apptest/features/notifications/domain/models/notification_model.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Requires Supabase Realtime enabled on tables: likes, connections.
// For the connections filter to work, the table needs REPLICA IDENTITY FULL
// (set in Supabase dashboard → Table Editor → connections → Replication).

class NotificationService {
  final SupabaseClient _client;
  final _localNotifs = FlutterLocalNotificationsPlugin();

  RealtimeChannel? _likesChannel;
  RealtimeChannel? _connectionsChannel;
  StreamSubscription<Position>? _positionSub;
  final Set<String> _notifiedProximityIds = {};
  bool _disposed = false;

  void Function(AppNotification)? _onNotification;

  NotificationService(this._client);

  Future<void> initialize({
    required void Function(AppNotification) onNotification,
  }) async {
    _onNotification = onNotification;
    await _initLocalNotifications();
    _subscribeLikes();
    _subscribeConnections();
    await _startProximityMonitoring();
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifs.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Request Android 13+ notification permission
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void _subscribeLikes() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _likesChannel = _client
        .channel('echo_likes_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'likes',
          callback: (payload) => _handleLike(payload, userId),
        )
        .subscribe();
  }

  Future<void> _handleLike(
    PostgresChangePayload payload,
    String userId,
  ) async {
    if (_disposed) return;
    final memoryId = payload.newRecord['memory_id'] as String?;
    final likerId = payload.newRecord['user_id'] as String?;
    if (memoryId == null || likerId == null || likerId == userId) return;

    // Verify this memory belongs to the current user
    final memory = await _client
        .from('memories')
        .select('user_id, description')
        .eq('id', memoryId)
        .eq('user_id', userId)
        .maybeSingle();
    if (memory == null || _disposed) return;

    final likerName = await _fetchDisplayName(likerId);
    final description = memory['description'] as String? ?? '';
    final shortDesc =
        description.length > 30 ? '${description.substring(0, 30)}…' : description;

    _emit(AppNotification(
      id: 'like_${memoryId}_$likerId',
      type: NotificationType.like,
      title: '$likerName ha messo like',
      body: '"$shortDesc"',
      createdAt: DateTime.now(),
      fromUserId: likerId,
      fromUsername: likerName,
      memoryId: memoryId,
    ));
  }

  void _subscribeConnections() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _connectionsChannel = _client
        .channel('echo_connections_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'connections',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'target_id',
            value: userId,
          ),
          callback: (payload) => _handleConnectionRequest(payload),
        )
        .subscribe();
  }

  Future<void> _handleConnectionRequest(PostgresChangePayload payload) async {
    if (_disposed) return;
    final requesterId = payload.newRecord['requester_id'] as String?;
    if (requesterId == null) return;

    final requesterName = await _fetchDisplayName(requesterId);

    _emit(AppNotification(
      id: 'connection_$requesterId',
      type: NotificationType.connectionRequest,
      title: 'Nuova richiesta di cerchia',
      body: '$requesterName vuole aggiungerti alla sua cerchia',
      createdAt: DateTime.now(),
      fromUserId: requesterId,
      fromUsername: requesterName,
    ));
  }

  Future<void> _startProximityMonitoring() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      ),
    ).listen(_onPositionUpdate);
  }

  Future<void> _onPositionUpdate(Position position) async {
    if (_disposed) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    const searchRadius = 1000.0;
    const metersPerDegree = 111320.0;
    final lat = position.latitude;
    final lng = position.longitude;
    final latDelta = searchRadius / metersPerDegree;
    final lngDelta = searchRadius / (metersPerDegree * cos(lat * pi / 180));

    try {
      final rows = await _client
          .from('memories')
          .select('id, description, latitude, longitude')
          .eq('visibility', 'circle')
          .neq('user_id', userId)
          .gte('latitude', lat - latDelta)
          .lte('latitude', lat + latDelta)
          .gte('longitude', lng - lngDelta)
          .lte('longitude', lng + lngDelta);

      for (final row in rows as List) {
        if (_disposed) return;
        final memoryId = row['id'] as String;
        if (_notifiedProximityIds.contains(memoryId)) continue;

        final memLat = (row['latitude'] as num).toDouble();
        final memLng = (row['longitude'] as num).toDouble();
        final dist = Geolocator.distanceBetween(lat, lng, memLat, memLng);

        if (dist <= MemoryModel.discoveryRadius) {
          _notifiedProximityIds.add(memoryId);
          final description = row['description'] as String? ?? '';
          final shortDesc = description.length > 30
              ? '${description.substring(0, 30)}…'
              : description;

          _emit(AppNotification(
            id: 'proximity_$memoryId',
            type: NotificationType.proximity,
            title: 'Ricordo nelle vicinanze',
            body: '"$shortDesc"',
            createdAt: DateTime.now(),
            memoryId: memoryId,
          ));
        }
      }
    } catch (_) {}
  }

  void _emit(AppNotification notification) {
    if (_disposed) return;
    _onNotification?.call(notification);
    _showLocalNotification(notification);
  }

  Future<void> _showLocalNotification(AppNotification notification) async {
    const androidDetails = AndroidNotificationDetails(
      'echo_channel',
      'Echo',
      channelDescription: 'Notifiche Echo',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _localNotifs.show(
      notification.id.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<String> _fetchDisplayName(String userId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('username, display_name')
          .eq('id', userId)
          .maybeSingle();
      if (profile == null) return 'Qualcuno';
      final display = profile['display_name'] as String?;
      return (display != null && display.isNotEmpty)
          ? display
          : (profile['username'] as String? ?? 'Qualcuno');
    } catch (_) {
      return 'Qualcuno';
    }
  }

  void dispose() {
    _disposed = true;
    _likesChannel?.unsubscribe();
    _connectionsChannel?.unsubscribe();
    _positionSub?.cancel();
  }
}
