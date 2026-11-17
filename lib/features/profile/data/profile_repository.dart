import 'package:echo/core/utils/image_sanitizer.dart';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';

const profilePublicColumns =
    'id, username, display_name, bio, avatar_url, memories_count, connections_count, created_at, updated_at, username_changed_at';

class ProfileRepository {
  final SupabaseClient _client;

  ProfileRepository(this._client);

  Future<ProfileModel?> getProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select(profilePublicColumns)
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return ProfileModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<ProfileModel> updateProfile({
    required String displayName,
    required String bio,
    String? avatarUrl,
    String? username,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final data = <String, dynamic>{
      'display_name': displayName,
      'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (username != null) data['username'] = username.trim().toLowerCase();

    final row = await _client
        .from('profiles')
        .update(data)
        .eq('id', userId)
        .select(profilePublicColumns)
        .single();

    return ProfileModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<String> uploadAvatar(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    // Path fisso per utente (non più timestamp): ogni upload sovrascrive il
    // precedente invece di lasciarlo orfano su Storage. Il timestamp in query
    // string serve solo a invalidare la cache immagine lato client, dato che
    // l'URL pubblico altrimenti resterebbe identico.
    final fileName = '$userId/avatar.jpg';
    final clean = await stripImageMetadata(bytes);
    await _client.storage
        .from('avatars')
        .uploadBinary(
          fileName,
          clean,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final publicUrl = _client.storage.from('avatars').getPublicUrl(fileName);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<bool> isUsernameAvailable(String username) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('username', username.toLowerCase())
        .maybeSingle();
    return row == null;
  }

  Future<List<ProfileModel>> searchUsersNearby({
    required String query,
    double? lat,
    double? lng,
    int pageSize = 20,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'search_users_nearby',
      params: {
        'search_query': query,
        'user_lat': ?lat,
        'user_lng': ?lng,
        'page_size': pageSize,
        'page_offset': offset,
      },
    );
    return (response as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _client.rpc('update_user_location', params: {'lat': lat, 'lng': lng});
  }
}
