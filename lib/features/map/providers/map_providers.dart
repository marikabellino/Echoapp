import 'package:echo/features/drop/domain/models/drop_model.dart';
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

typedef MapFlyTarget = ({double lat, double lng, DropModel drop});

class MapFlyTargetNotifier extends Notifier<MapFlyTarget?> {
  @override
  MapFlyTarget? build() => null;

  void set(DropModel drop) =>
      state = (lat: drop.latitude, lng: drop.longitude, drop: drop);
  void clear() => state = null;
}

final mapFlyTargetProvider =
    NotifierProvider<MapFlyTargetNotifier, MapFlyTarget?>(
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

// ─── Tab re-tap signal (tapping the already-active navbar icon) ───────────────

/// Fired when the user taps the navbar icon of the tab they're already on
/// (e.g. Instagram-style "tap again to scroll to top"). [nonce] always
/// changes so listeners fire even on repeated taps of the same tab.
class TabRetapNotifier extends Notifier<({int index, int nonce})?> {
  @override
  ({int index, int nonce})? build() => null;

  void ping(int index) {
    state = (index: index, nonce: (state?.nonce ?? 0) + 1);
  }
}

final tabRetapProvider =
    NotifierProvider<TabRetapNotifier, ({int index, int nonce})?>(
      TabRetapNotifier.new,
    );
