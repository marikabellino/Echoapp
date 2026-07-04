import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echo/features/events/domain/models/event_model.dart';

class EventsRepository {
  final SupabaseClient _client;

  EventsRepository(this._client);

  static const _dropSelect = '''
    *,
    profiles:user_id (
      id, username, display_name, avatar_url, memories_count, connections_count
    ),
    event:event_id ( id, title )
  ''';

  static double _earthDistanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earthRadius * 2 * asin(sqrt(a));
  }

  /// Eventi ancora attivi o terminati da meno di 24h, entro il loro
  /// raggio dalla posizione data.
  Future<List<EventModel>> getNearbyActiveEvents({
    required double lat,
    required double lng,
  }) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final rows = await _client
        .from('events')
        .select()
        .gte('ends_at', cutoff.toIso8601String())
        .order('starts_at');

    final events = rows
        .map((r) => EventModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .where(
          (e) =>
              _earthDistanceMeters(lat, lng, e.latitude, e.longitude) <=
              e.radiusMeters,
        )
        .toList();

    return events;
  }

  Future<List<DropModel>> getEventDrops(String eventId) async {
    final rows = await _client
        .from('memories')
        .select(_dropSelect)
        .eq('event_id', eventId)
        .neq('visibility', 'private')
        .order('created_at', ascending: false);

    return rows
        .map((r) => DropModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
