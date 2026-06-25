import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';

class ProfileRepository {
  final SupabaseClient _client;

  ProfileRepository(this._client);

  Future<ProfileModel?> getProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return ProfileModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<ProfileModel> updateProfile({
    required String displayName,
    required String bio,
    String? avatarUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final data = <String, dynamic>{
      'display_name': displayName,
      'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;

    final row = await _client
        .from('profiles')
        .update(data)
        .eq('id', userId)
        .select()
        .single();

    return ProfileModel.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<String> uploadAvatar(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('avatars').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return _client.storage.from('avatars').getPublicUrl(fileName);
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
    final response = await _client.rpc('search_users_nearby', params: {
      'search_query': query,
      'user_lat': ?lat,
      'user_lng': ?lng,
      'page_size': pageSize,
      'page_offset': offset,
    });
    return (response as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _client.rpc('update_user_location', params: {
      'lat': lat,
      'lng': lng,
    });
  }
}
