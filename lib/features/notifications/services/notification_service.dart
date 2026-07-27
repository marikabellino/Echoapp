import 'dart:async';
import 'dart:math' show cos, pi;

import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Gestisce le notifiche IN-APP via Supabase Realtime + prossimità.
// Il delivery in background/killed è delegato a FCM (FcmService).

class NotificationService {
  final SupabaseClient _client;

  RealtimeChannel? _likesChannel;
  RealtimeChannel? _connectionsChannel;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _tagsChannel;
  RealtimeChannel? _dropsChannel;
  RealtimeChannel? _commentTagsChannel;
  StreamSubscription<Position>? _positionSub;
  final Set<String> _notifiedProximityIds = {};
  bool _disposed = false;

  void Function(AppNotification)? _onNotification;

  NotificationService(this._client);

  Future<void> initialize({
    required void Function(AppNotification) onNotification,
  }) async {
    _onNotification = onNotification;
    _subscribeLikes();
    _subscribeConnections();
    _subscribeMessages();
    _subscribeTags();
    _subscribeCircleDrops();
    _subscribeCommentTags();
    await _startProximityMonitoring();
  }

  // ─── Likes ────────────────────────────────────────────────────────────────

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
    final dropId = payload.newRecord['memory_id'] as String?;
    final likerId = payload.newRecord['user_id'] as String?;
    if (dropId == null || likerId == null || likerId == userId) return;

    final drop = await _client
        .from('memories')
        .select('user_id, description')
        .eq('id', dropId)
        .eq('user_id', userId)
        .maybeSingle();
    if (drop == null || _disposed) return;

    final likerName = await _fetchDisplayName(likerId);
    final description = drop['description'] as String? ?? '';
    final shortDesc = description.length > 30
        ? '${description.substring(0, 30)}…'
        : description;

    _emit(AppNotification(
      id: 'like_${dropId}_$likerId',
      type: NotificationType.like,
      title: '$likerName ha messo like',
      body: '"$shortDesc"',
      createdAt: DateTime.now(),
      fromUserId: likerId,
      fromUsername: likerName,
      dropId: dropId,
    ));
  }

  // ─── Connections ──────────────────────────────────────────────────────────

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

  // ─── Tags ─────────────────────────────────────────────────────────────────

  void _subscribeTags() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _tagsChannel = _client
        .channel('echo_tags_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'drop_tags',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tagged_user_id',
            value: userId,
          ),
          callback: (payload) => _handleTagged(payload),
        )
        .subscribe();
  }

  Future<void> _handleTagged(PostgresChangePayload payload) async {
    if (_disposed) return;
    final dropId = payload.newRecord['drop_id'] as String?;
    final taggedById = payload.newRecord['tagged_by'] as String?;
    if (dropId == null || taggedById == null) return;

    final taggerName = await _fetchDisplayName(taggedById);
    if (_disposed) return;

    _emit(AppNotification(
      id: 'tagged_${dropId}_$taggedById',
      type: NotificationType.tagged,
      title: 'Sei stato taggato',
      body: '$taggerName ti ha taggato in un drop',
      createdAt: DateTime.now(),
      fromUserId: taggedById,
      fromUsername: taggerName,
      dropId: dropId,
    ));
  }

  // ─── Circle drops ─────────────────────────────────────────────────────────
  //
  // Nessun filtro sulla subscription (come per i messaggi): la RLS
  // "Memories: read" decide già lato server quali insert arrivano a questo
  // client (proprio drop, pubblico, cerchia connessa, o taggato) — qui ci
  // interessa solo il sottoinsieme "cerchia", filtrato client-side.

  void _subscribeCircleDrops() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _dropsChannel = _client
        .channel('echo_drops_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'memories',
          callback: (payload) => _handleNewCircleDrop(payload, userId),
        )
        .subscribe();
  }

  Future<void> _handleNewCircleDrop(
    PostgresChangePayload payload,
    String userId,
  ) async {
    if (_disposed) return;
    final authorId = payload.newRecord['user_id'] as String?;
    final visibility = payload.newRecord['visibility'] as String?;
    final dropId = payload.newRecord['id'] as String?;
    if (authorId == null ||
        authorId == userId ||
        visibility != 'circle' ||
        dropId == null) {
      return;
    }

    final authorName = await _fetchDisplayName(authorId);
    if (_disposed) return;

    final description = payload.newRecord['description'] as String? ?? '';
    final shortDesc = description.length > 30
        ? '${description.substring(0, 30)}…'
        : description;

    _emit(AppNotification(
      id: 'circle_drop_$dropId',
      type: NotificationType.circleDrop,
      title: '$authorName ha lasciato un drop',
      body: shortDesc.isEmpty ? 'Nella tua cerchia' : '"$shortDesc"',
      createdAt: DateTime.now(),
      fromUserId: authorId,
      fromUsername: authorName,
      dropId: dropId,
    ));
  }

  // ─── Comment tags ─────────────────────────────────────────────────────────

  void _subscribeCommentTags() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _commentTagsChannel = _client
        .channel('echo_comment_tags_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'comment_tags',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tagged_user_id',
            value: userId,
          ),
          callback: (payload) => _handleCommentTagged(payload),
        )
        .subscribe();
  }

  Future<void> _handleCommentTagged(PostgresChangePayload payload) async {
    if (_disposed) return;
    final commentId = payload.newRecord['comment_id'] as String?;
    final taggedById = payload.newRecord['tagged_by'] as String?;
    if (commentId == null || taggedById == null) return;

    final comment = await _client
        .from('comments')
        .select('memory_id')
        .eq('id', commentId)
        .maybeSingle();
    if (comment == null || _disposed) return;
    final dropId = comment['memory_id'] as String?;

    final taggerName = await _fetchDisplayName(taggedById);
    if (_disposed) return;

    _emit(AppNotification(
      id: 'comment_tagged_${commentId}_$taggedById',
      type: NotificationType.commentTagged,
      title: 'Sei stato taggato in un commento',
      body: '$taggerName ti ha taggato in un commento',
      createdAt: DateTime.now(),
      fromUserId: taggedById,
      fromUsername: taggerName,
      dropId: dropId,
    ));
  }

  // ─── Messages ─────────────────────────────────────────────────────────────

  void _subscribeMessages() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _messagesChannel = _client
        .channel('echo_messages_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _handleNewMessage(payload, userId),
        )
        .subscribe();
  }

  Future<void> _handleNewMessage(
    PostgresChangePayload payload,
    String userId,
  ) async {
    if (_disposed) return;
    final senderId = payload.newRecord['sender_id'] as String?;
    final conversationId = payload.newRecord['conversation_id'] as String?;
    final content = payload.newRecord['content'] as String?;
    final messageId = payload.newRecord['id'] as String?;

    if (senderId == null ||
        conversationId == null ||
        content == null ||
        messageId == null) {
      return;
    }
    if (senderId == userId) return;

    final senderName = await _fetchDisplayName(senderId);
    if (_disposed) return;

    final shortContent =
        content.length > 40 ? '${content.substring(0, 40)}…' : content;

    _emit(AppNotification(
      id: 'message_$messageId',
      type: NotificationType.message,
      title: senderName,
      body: shortContent,
      createdAt: DateTime.now(),
      fromUserId: senderId,
      fromUsername: senderName,
      conversationId: conversationId,
    ));
  }

  // ─── Proximity ────────────────────────────────────────────────────────────

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
        final dropId = row['id'] as String;
        if (_notifiedProximityIds.contains(dropId)) continue;

        final dropLat = (row['latitude'] as num).toDouble();
        final dropLng = (row['longitude'] as num).toDouble();
        final dist = Geolocator.distanceBetween(lat, lng, dropLat, dropLng);

        if (dist <= DropModel.discoveryRadius) {
          _notifiedProximityIds.add(dropId);
          final description = row['description'] as String? ?? '';
          final shortDesc = description.length > 30
              ? '${description.substring(0, 30)}…'
              : description;

          _emit(AppNotification(
            id: 'proximity_$dropId',
            type: NotificationType.proximity,
            title: 'Drop nelle vicinanze',
            body: '"$shortDesc"',
            createdAt: DateTime.now(),
            dropId: dropId,
          ));
        }
      }
    } catch (_) {}
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _emit(AppNotification notification) {
    if (_disposed) return;
    _onNotification?.call(notification);
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
    _messagesChannel?.unsubscribe();
    _tagsChannel?.unsubscribe();
    _dropsChannel?.unsubscribe();
    _commentTagsChannel?.unsubscribe();
    _positionSub?.cancel();
  }
}
