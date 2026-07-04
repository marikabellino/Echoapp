import 'dart:convert';

import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DropCacheService {
  final SharedPreferences _prefs;
  DropCacheService(this._prefs);

  static const _prefix = 'echo_drop_cache_';

  Future<void> saveUserDrops(String userId, List<DropModel> drops) async {
    final json = drops.map((m) => m.toJson()).toList();
    await _prefs.setString(_prefix + userId, jsonEncode(json));
  }

  List<DropModel> loadUserDrops(String userId) {
    final raw = _prefs.getString(_prefix + userId);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DropModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPreferencesProvider in main.dart');
});

final dropCacheServiceProvider = Provider<DropCacheService>((ref) {
  return DropCacheService(ref.watch(sharedPreferencesProvider));
});
