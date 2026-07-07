import 'dart:math' show cos, pi;
import 'dart:typed_data';

import 'package:echo/features/drop/domain/models/comment_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';

class DropRepository {
  final SupabaseClient _client;

  DropRepository(this._client);

  static const _select = '''
    *,
    profiles:user_id (
      id, username, display_name, avatar_url, memories_count, connections_count
    ),
    event:event_id ( id, title )
  ''';

  Future<List<DropModel>> getDiscoverDrops({
    int limit = 20,
    int offset = 0,
  }) async {
    await _downgradeExpiredEventDrops();

    final rows = await _client
        .from('memories')
        .select(_select)
        .neq('visibility', 'private')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final drops = _parseRows(rows);
    return _hydrateWithLikes(drops);
  }

  // I drop agganciati a un evento nascono 'public' e restano tali finché
  // l'evento è attivo; una volta concluso tornano 'circle' (visibili solo
  // all'autore e alla sua cerchia). Nessun cron: si chiama a ogni fetch dei
  // drop, così il downgrade avviene con la normale attività dell'app.
  Future<void> _downgradeExpiredEventDrops() async {
    try {
      await _client.rpc('downgrade_expired_event_drops');
    } catch (_) {
      // Non bloccante: se fallisce, si ritenterà al prossimo fetch.
    }
  }

  Future<List<DropModel>> getNearbyDrops({
    required double lat,
    required double lng,
    double radiusMeters = 5000,
    Set<String> visibilities = const {'public'},
  }) async {
    const metersPerDegree = 111320.0;
    final latDelta = radiusMeters / metersPerDegree;
    final lngDelta = radiusMeters / (metersPerDegree * cos(lat * pi / 180));

    final result = <DropModel>[];

    // Fetch public + circle drops
    final nonPrivate = visibilities.where((v) => v != 'private').toList();
    if (nonPrivate.isNotEmpty) {
      final rows = await _client
          .from('memories')
          .select(_select)
          .inFilter('visibility', nonPrivate)
          .gte('latitude', lat - latDelta)
          .lte('latitude', lat + latDelta)
          .gte('longitude', lng - lngDelta)
          .lte('longitude', lng + lngDelta)
          .order('created_at', ascending: false)
          .limit(50);
      result.addAll(_parseRows(rows));
    }

    // Fetch private (only own drops)
    if (visibilities.contains('private')) {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        final rows = await _client
            .from('memories')
            .select(_select)
            .eq('visibility', 'private')
            .eq('user_id', userId)
            .gte('latitude', lat - latDelta)
            .lte('latitude', lat + latDelta)
            .gte('longitude', lng - lngDelta)
            .lte('longitude', lng + lngDelta)
            .order('created_at', ascending: false)
            .limit(50);
        result.addAll(_parseRows(rows));
      }
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result.take(100).toList();
  }

  Future<List<DropModel>> getUserDrops(String userId) async {
    await _downgradeExpiredEventDrops();

    final rows = await _client
        .from('memories')
        .select(_select)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return _hydrateWithLikes(_parseRows(rows));
  }

  Future<DropModel?> getDropById(String dropId) async {
    final rows = await _client
        .from('memories')
        .select(_select)
        .eq('id', dropId)
        .limit(1);
    final list = _parseRows(rows);
    return list.isEmpty ? null : list.first;
  }

  Future<DropModel> createDrop({
    required String description,
    required DropMood mood,
    required double latitude,
    required double longitude,
    String? locationName,
    String? imageUrl,
    String? aiCaption,
    DropVisibility visibility = DropVisibility.public,
    String? eventId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final row = await _client
        .from('memories')
        .insert({
          'user_id': userId,
          'description': description,
          'mood': mood.value,
          'latitude': latitude,
          'longitude': longitude,
          'location_name': locationName,
          'image_url': imageUrl,
          'ai_caption': aiCaption,
          'visibility': visibility.value,
          'event_id': ?eventId,
        })
        .select(_select)
        .single();

    return DropModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> toggleLike(String dropId, {required bool isLiked}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    if (isLiked) {
      await _client.from('likes').delete().match({
        'user_id': userId,
        'memory_id': dropId,
      });
    } else {
      await _client.from('likes').insert({
        'user_id': userId,
        'memory_id': dropId,
      });
    }
  }

  Future<void> deleteDrop(String dropId) async {
    await _client.from('memories').delete().eq('id', dropId);
  }

  Future<void> reportDrop(String dropId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('reports').upsert({
      'reporter_id': userId,
      'memory_id': dropId,
    }, onConflict: 'reporter_id,memory_id');
  }

  Future<String> uploadDropImage(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage
        .from('memories')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return _client.storage.from('memories').getPublicUrl(fileName);
  }

  // ─── Tag persone ──────────────────────────────────────────────────────────────

  // Ritorna gli id effettivamente taggati: la RPC scarta silenziosamente chi
  // non è nella cerchia accettata del chiamante o è bloccato, quindi il
  // chiamante deve poter confrontare userIds col risultato per sapere chi
  // è stato escluso e perché.
  Future<List<String>> tagUsersOnDrop(
    String dropId,
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return [];
    final rows = await _client.rpc(
      'tag_users_on_drop',
      params: {'p_drop_id': dropId, 'p_user_ids': userIds},
    );
    return (rows as List<dynamic>)
        .map((r) => (r as Map)['tagged_user_id'] as String)
        .toList();
  }

  Future<List<ProfileModel>> getDropTags(String dropId) async {
    final rows = await _client.rpc(
      'get_drop_tags',
      params: {'p_drop_id': dropId},
    );
    return (rows as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<DropModel>> getTaggedDrops(String userId) async {
    final rows = await _client
        .from('drop_tags')
        .select('created_at, memories($_select)')
        .eq('tagged_user_id', userId)
        .eq('hidden_by_tagged', false)
        .order('created_at', ascending: false);

    final drops = (rows as List<dynamic>)
        .map((r) => (r as Map)['memories'])
        .whereType<Map>()
        .map((m) => DropModel.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return _hydrateWithLikes(drops);
  }

  Future<void> setTagHidden(String dropId, {required bool hidden}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('drop_tags').update({'hidden_by_tagged': hidden}).match({
      'drop_id': dropId,
      'tagged_user_id': userId,
    });
  }

  // ─── Comments ────────────────────────────────────────────────────────────────

  Future<List<CommentModel>> getComments(String dropId) async {
    final rows = await _client
        .from('comments')
        .select('*, profiles:user_id(id, username, display_name, avatar_url)')
        .eq('memory_id', dropId)
        .order('created_at', ascending: true);
    return (rows as List<dynamic>)
        .map((r) => CommentModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> addComment(String dropId, String content) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('comments').insert({
      'memory_id': dropId,
      'user_id': userId,
      'content': content.trim(),
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _client.from('comments').delete().eq('id', commentId);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  List<DropModel> _parseRows(List<dynamic> rows) => rows
      .map((r) => DropModel.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();

  Future<List<DropModel>> _hydrateWithLikes(List<DropModel> drops) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || drops.isEmpty) return drops;

    final ids = drops.map((m) => m.id).toList();
    final likes = await _client
        .from('likes')
        .select('memory_id')
        .eq('user_id', userId)
        .inFilter('memory_id', ids);

    final likedIds = {for (final l in likes as List) l['memory_id'] as String};
    return drops
        .map((m) => m.copyWith(isLikedByMe: likedIds.contains(m.id)))
        .toList();
  }
}
