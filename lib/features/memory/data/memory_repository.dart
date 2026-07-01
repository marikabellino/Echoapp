import 'dart:math' show cos, pi;
import 'dart:typed_data';

import 'package:echo/features/memory/domain/models/comment_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';

class MemoryRepository {
  final SupabaseClient _client;

  MemoryRepository(this._client);

  static const _select = '''
    *,
    profiles:user_id (
      id, username, display_name, avatar_url, memories_count, connections_count
    )
  ''';

  Future<List<MemoryModel>> getDiscoverMemories({
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _client
        .from('memories')
        .select(_select)
        .neq('visibility', 'private')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final memories = _parseRows(rows);
    return _hydrateWithLikes(memories);
  }

  Future<List<MemoryModel>> getNearbyMemories({
    required double lat,
    required double lng,
    double radiusMeters = 5000,
    Set<String> visibilities = const {'public'},
  }) async {
    const metersPerDegree = 111320.0;
    final latDelta = radiusMeters / metersPerDegree;
    final lngDelta = radiusMeters / (metersPerDegree * cos(lat * pi / 180));

    final result = <MemoryModel>[];

    // Fetch public + circle memories
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

    // Fetch private (only own memories)
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

  Future<List<MemoryModel>> getUserMemories(String userId) async {
    final rows = await _client
        .from('memories')
        .select(_select)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return _hydrateWithLikes(_parseRows(rows));
  }

  Future<MemoryModel> createMemory({
    required String description,
    required MemoryMood mood,
    required double latitude,
    required double longitude,
    String? locationName,
    String? imageUrl,
    String? aiCaption,
    MemoryVisibility visibility = MemoryVisibility.public,
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
        })
        .select(_select)
        .single();

    return MemoryModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> toggleLike(String memoryId, {required bool isLiked}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    if (isLiked) {
      await _client
          .from('likes')
          .delete()
          .match({'user_id': userId, 'memory_id': memoryId});
    } else {
      await _client
          .from('likes')
          .insert({'user_id': userId, 'memory_id': memoryId});
    }
  }

  Future<void> deleteMemory(String memoryId) async {
    await _client.from('memories').delete().eq('id', memoryId);
  }

  Future<void> reportMemory(String memoryId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('reports').upsert(
      {'reporter_id': userId, 'memory_id': memoryId},
      onConflict: 'reporter_id,memory_id',
    );
  }

  Future<String> uploadMemoryImage(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('memories').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
    );
    return _client.storage.from('memories').getPublicUrl(fileName);
  }

  // ─── Comments ────────────────────────────────────────────────────────────────

  Future<List<CommentModel>> getComments(String memoryId) async {
    final rows = await _client
        .from('comments')
        .select('*, profiles:user_id(id, username, display_name, avatar_url)')
        .eq('memory_id', memoryId)
        .order('created_at', ascending: true);
    return (rows as List<dynamic>)
        .map((r) => CommentModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> addComment(String memoryId, String content) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('comments').insert({
      'memory_id': memoryId,
      'user_id': userId,
      'content': content.trim(),
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _client.from('comments').delete().eq('id', commentId);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  List<MemoryModel> _parseRows(List<dynamic> rows) => rows
      .map((r) => MemoryModel.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();

  Future<List<MemoryModel>> _hydrateWithLikes(List<MemoryModel> memories) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || memories.isEmpty) return memories;

    final ids = memories.map((m) => m.id).toList();
    final likes = await _client
        .from('likes')
        .select('memory_id')
        .eq('user_id', userId)
        .inFilter('memory_id', ids);

    final likedIds = {
      for (final l in likes as List) l['memory_id'] as String,
    };
    return memories
        .map((m) => m.copyWith(isLikedByMe: likedIds.contains(m.id)))
        .toList();
  }
}
