import 'dart:convert';

import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryCacheService {
  final SharedPreferences _prefs;
  MemoryCacheService(this._prefs);

  static const _prefix = 'echo_mem_cache_';

  Future<void> saveUserMemories(String userId, List<MemoryModel> memories) async {
    final json = memories.map((m) => m.toJson()).toList();
    await _prefs.setString(_prefix + userId, jsonEncode(json));
  }

  List<MemoryModel> loadUserMemories(String userId) {
    final raw = _prefs.getString(_prefix + userId);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MemoryModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPreferencesProvider in main.dart');
});

final memoryCacheServiceProvider = Provider<MemoryCacheService>((ref) {
  return MemoryCacheService(ref.watch(sharedPreferencesProvider));
});
