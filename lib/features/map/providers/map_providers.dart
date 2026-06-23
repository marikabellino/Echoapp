import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Map create location ──────────────────────────────────────────────────────

class MapCreateLocationNotifier extends Notifier<({double lat, double lng})?> {
  @override
  ({double lat, double lng})? build() => null;

  void set(double lat, double lng) => state = (lat: lat, lng: lng);
  void clear() => state = null;
}

final mapCreateLocationProvider =
    NotifierProvider<MapCreateLocationNotifier, ({double lat, double lng})?>(
  MapCreateLocationNotifier.new,
);

// ─── Map fly target (from Scopri) ────────────────────────────────────────────

typedef MapFlyTarget = ({double lat, double lng, MemoryModel memory});

class MapFlyTargetNotifier extends Notifier<MapFlyTarget?> {
  @override
  MapFlyTarget? build() => null;

  void set(MemoryModel memory) =>
      state = (lat: memory.latitude, lng: memory.longitude, memory: memory);
  void clear() => state = null;
}

final mapFlyTargetProvider = NotifierProvider<MapFlyTargetNotifier, MapFlyTarget?>(
  MapFlyTargetNotifier.new,
);

// ─── Shell (tab) index ────────────────────────────────────────────────────────

class ShellIndexNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setIndex(int index) => state = index;
}

final shellIndexProvider = NotifierProvider<ShellIndexNotifier, int>(
  ShellIndexNotifier.new,
);

// ─── Scroll offset for navbar animation ──────────────────────────────────────

class ScrollOffsetNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void updateOffset(double offset) => state = offset;
  void reset() => state = 0.0;
}

final scrollOffsetProvider = NotifierProvider<ScrollOffsetNotifier, double>(
  ScrollOffsetNotifier.new,
);
