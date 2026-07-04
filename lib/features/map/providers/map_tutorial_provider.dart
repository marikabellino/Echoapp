import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'map_tutorial_v1_seen';

class MapTutorialNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
    state = const AsyncData(true);
  }
}

final mapTutorialProvider = AsyncNotifierProvider<MapTutorialNotifier, bool>(
  MapTutorialNotifier.new,
);
