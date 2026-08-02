import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/services/permission_gate.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/map/presentation/widgets/map_tutorial_overlay.dart';
import 'package:echo/features/map/providers/map_tutorial_provider.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:vibration/vibration.dart';

// ─── Cluster ──────────────────────────────────────────────────────────────────

class _DropCluster {
  final List<DropModel> drops;
  final double lat;
  final double lng;

  const _DropCluster({
    required this.drops,
    required this.lat,
    required this.lng,
  });

  bool get isSingle => drops.length == 1;
  DropModel get first => drops.first;

  String get key => (drops.map((m) => m.id).toList()..sort()).join(',');
}

List<_DropCluster> _buildClusters(
  List<DropModel> drops, {
  double radiusMeters = 20.0,
}) {
  final result = <_DropCluster>[];
  final assigned = <String>{};

  for (final m in drops) {
    if (assigned.contains(m.id)) continue;
    final group = <DropModel>[m];
    assigned.add(m.id);

    for (final other in drops) {
      if (assigned.contains(other.id)) continue;
      final dist = geo.Geolocator.distanceBetween(
        m.latitude,
        m.longitude,
        other.latitude,
        other.longitude,
      );
      if (dist <= radiusMeters) {
        group.add(other);
        assigned.add(other.id);
      }
    }

    final avgLat =
        group.map((e) => e.latitude).reduce((a, b) => a + b) / group.length;
    final avgLng =
        group.map((e) => e.longitude).reduce((a, b) => a + b) / group.length;
    result.add(_DropCluster(drops: group, lat: avgLat, lng: avgLng));
  }
  return result;
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _mapController;

  // symbol → cluster (single or multi drop)
  final Map<Symbol, _DropCluster> _symbolMap = {};

  // mood → pre-rendered PNG bytes (rendered once, re-registered on style reload)
  final Map<DropMood, Uint8List> _moodImages = {};

  // count → pre-rendered cluster badge PNG bytes
  final Map<int, Uint8List> _clusterImages = {};

  // dropId → pre-rendered PNG bytes for pins whose photo preview has loaded
  final Map<String, Uint8List> _photoPinImages = {};

  // dropIds currently being fetched/rendered, to avoid duplicate work
  final Set<String> _photoFetchInFlight = {};

  Set<DropVisibility> _selectedVisibilities = {DropVisibility.public};

  bool _showMarkers = false;
  bool _showCrosshair = false;
  bool _dropDiscovered = false;
  bool _mapReady = false;
  bool _viewportLoadEnabled = false;
  geo.Position? _userPosition;
  List<DropModel> _drops = [];
  DropModel? _selectedDrop;
  MapFlyTarget? _pendingFlyTarget;

  // tracks whether the initial fly-to-user has happened (avoids re-flying on style reload)
  bool _initialRevealDone = false;

  // real on-screen positions for the guided tour arrows (measured via keys)
  final _filterRowKey = GlobalKey();
  final _cardAreaKey = GlobalKey();
  final _addButtonKey = GlobalKey();
  Map<int, Offset>? _tutorialTargets;

  // prevents concurrent _syncAnnotations calls from interleaving
  bool _syncing = false;

  // swipe-to-dismiss state (reel-style vertical swipe)
  int _dismissedCount = 0;
  double _dragOffset = 0;
  bool _isDismissing = false;
  double _dismissStartOffset = 0;
  late final AnimationController _dismissCtrl;

  @override
  void initState() {
    super.initState();
    _dismissCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _loadNearby();
  }

  @override
  void dispose() {
    _dismissCtrl.dispose();
    super.dispose();
  }

  // ─── Pin shape ─────────────────────────────────────────────────────────────
  //
  // Classic map "teardrop" outline: a circular head with two lines tangent
  // to it converging to a point below, closed by an arc over the top of the
  // circle. Tangency keeps the join between the straight tail and the head
  // visually seamless (no kink where they meet).

  Path _teardropPath({
    required Offset center,
    required double r,
    required double tipDistance,
  }) {
    final angle = math.acos((r / tipDistance).clamp(-1.0, 1.0));
    final rightAngle = math.pi / 2 - angle;
    final leftAngle = math.pi / 2 + angle;
    final tip = Offset(center.dx, center.dy + tipDistance);
    final right = Offset(
      center.dx + r * math.cos(rightAngle),
      center.dy + r * math.sin(rightAngle),
    );
    // Sweep the long way around (over the top), not through the tail gap.
    final sweep = (leftAngle - rightAngle) - 2 * math.pi;

    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: r), rightAngle, sweep, false)
      ..lineTo(tip.dx, tip.dy)
      ..close();
  }

  void _drawIconGlyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  // ─── Single-drop pin rendering ─────────────────────────────────────────────

  Future<void> _preRenderMoodImages() async {
    for (final mood in DropMood.values) {
      _moodImages[mood] = await _renderSinglePin(mood);
    }
  }

  /// Renders a downward-pointing pin. When [photo] is supplied it fills the
  /// inner preview circle (cover-fit); otherwise the mood's outline icon is
  /// used as a fallback while the photo loads (or when there isn't one).
  Future<Uint8List> _renderSinglePin(DropMood mood, {ui.Image? photo}) async {
    const double r = 70.0;
    const double tipDistance = 98.0;
    const double sidePad = 20.0;
    const double topPad = 20.0;
    const double width = r * 2 + sidePad * 2;
    const double height = topPad + r + tipDistance + 3.0;
    final color = mood.color;
    // The teardrop body itself reads as a muted, semi-transparent grey shell;
    // the mood color stays vivid only on the inner preview circle/icon.
    final bodyColor = Color.lerp(color, Colors.blueGrey.shade400, 0.55)!
        .withValues(alpha: 0.68);
    const center = Offset(width / 2, topPad + r);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    final path = _teardropPath(center: center, r: r, tipDistance: tipDistance);

    // Drop shadow
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    // Outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = bodyColor.withValues(alpha: 0.22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    // Body fill
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-r * 0.3, -r * 0.35),
          r * 1.6,
          [
            Color.lerp(Colors.white, bodyColor, 0.35)!,
            bodyColor,
            Color.lerp(bodyColor, Colors.black, 0.2)!.withValues(alpha: 0.68),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    // Rim highlight
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Inner preview circle
    const innerR = r * 0.66;
    canvas.drawCircle(
      center,
      innerR + 2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: innerR)));
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: center, radius: innerR),
        image: photo,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(center, innerR, Paint()..color = color.withValues(alpha: 0.18));
      _drawIconGlyph(canvas, mood.icon, center, innerR * 1.1, color);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<ui.Image> _loadNetworkImage(String url) {
    final completer = Completer<ui.Image>();
    final stream = CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Kicks off (at most once per drop) fetching the photo preview and
  /// swapping the already-shown fallback pin for the photo pin in place.
  void _ensurePhotoPin(DropModel drop) {
    final id = drop.id;
    final url = drop.imageUrl;
    if (url == null) return;
    if (_photoPinImages.containsKey(id) || _photoFetchInFlight.contains(id)) return;

    _photoFetchInFlight.add(id);
    _loadNetworkImage(url)
        .then((image) async {
          final bytes = await _renderSinglePin(drop.mood, photo: image);
          if (!mounted) return;
          _photoPinImages[id] = bytes;
          final ctrl = _mapController;
          if (ctrl == null) return;
          try {
            await ctrl.addImage('pin-photo-$id', bytes);
          } catch (_) {
            return;
          }
          for (final entry in _symbolMap.entries) {
            if (entry.value.isSingle && entry.value.first.id == id) {
              try {
                await ctrl.updateSymbol(
                  entry.key,
                  SymbolOptions(iconImage: 'pin-photo-$id'),
                );
              } catch (_) {}
              break;
            }
          }
        })
        .catchError((_) {})
        .whenComplete(() => _photoFetchInFlight.remove(id));
  }

  // ─── Cluster pin rendering ─────────────────────────────────────────────────

  Future<Uint8List> _renderClusterPin(int count) async {
    const double r = 70.0;
    const double tipDistance = 98.0;
    const double sidePad = 24.0;
    const double topPad = 24.0;
    const double width = r * 2 + sidePad * 2;
    const double height = topPad + r + tipDistance + 3.0;
    const color = Color(0xFF33CCBD);
    // The teardrop body itself reads as a muted, semi-transparent grey shell;
    // the accent color stays solid only on the inner count circle.
    final bodyColor = Color.lerp(color, Colors.blueGrey.shade400, 0.55)!
        .withValues(alpha: 0.68);
    const center = Offset(width / 2, topPad + r);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    final path = _teardropPath(center: center, r: r, tipDistance: tipDistance);

    // Drop shadow
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.26)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    // Outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = bodyColor.withValues(alpha: 0.24)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );
    // Body fill
    canvas.drawPath(path, Paint()..color = bodyColor);
    // Rim highlight
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.4),
    );

    // Inner count circle
    const innerR = r * 0.62;
    canvas.drawCircle(
      center,
      innerR + 3,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawCircle(center, innerR, Paint()..color = color);

    final label = count > 99 ? '99+' : '$count';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: innerR * (label.length > 2 ? 0.85 : 1.05),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ─── Style loaded — called at init and on every style change ─────────────

  Future<void> _onStyleLoaded() async {
    // Symbols are wiped when the style reloads; clear stale references
    _symbolMap.clear();

    if (_moodImages.isEmpty) {
      await _preRenderMoodImages();
    }
    // Re-register mood images into the new style
    for (final entry in _moodImages.entries) {
      try {
        await _mapController!.addImage('mood-${entry.key.name}', entry.value);
      } catch (_) {}
    }
    // Re-register cluster images into the new style
    for (final entry in _clusterImages.entries) {
      try {
        await _mapController!.addImage('cluster-${entry.key}', entry.value);
      } catch (_) {}
    }
    // Re-register already-loaded photo pins into the new style
    for (final entry in _photoPinImages.entries) {
      try {
        await _mapController!.addImage('pin-photo-${entry.key}', entry.value);
      } catch (_) {}
    }

    _mapReady = true;
    if (!_initialRevealDone) {
      _initialRevealDone = true;
      if (mounted && _userPosition != null) await _flyToUserAndReveal();
    } else if (_showMarkers) {
      await _syncAnnotations();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTutorialTargets();
    });
  }

  // ─── Annotation sync ──────────────────────────────────────────────────────

  Future<void> _syncAnnotations() async {
    final ctrl = _mapController;
    if (ctrl == null || !_showMarkers || _syncing) return;
    _syncing = true;

    try {
      final clusters = _buildClusters(_drops);
      final targetKeys = clusters.map((c) => c.key).toSet();
      final shownKeys = _symbolMap.values.map((c) => c.key).toSet();

      // 1 — Add new clusters FIRST so there's never a gap on screen
      for (final cluster in clusters) {
        if (shownKeys.contains(cluster.key)) continue;

        final String imageKey;
        if (cluster.isSingle) {
          final drop = cluster.first;
          if (_moodImages[drop.mood] == null) continue;
          final hasPhoto = _photoPinImages.containsKey(drop.id);
          imageKey = hasPhoto ? 'pin-photo-${drop.id}' : 'mood-${drop.mood.name}';
        } else {
          final count = cluster.drops.length;
          final cacheKey = 'cluster-$count';
          if (!_clusterImages.containsKey(count)) {
            final bytes = await _renderClusterPin(count);
            _clusterImages[count] = bytes;
            try {
              await ctrl.addImage(cacheKey, bytes);
            } catch (_) {}
          }
          imageKey = cacheKey;
        }

        try {
          final sym = await ctrl.addSymbol(
            SymbolOptions(
              geometry: LatLng(cluster.lat, cluster.lng),
              iconImage: imageKey,
              iconSize: 1.0,
              iconAnchor: 'bottom',
            ),
          );
          _symbolMap[sym] = cluster;
        } catch (_) {}

        if (cluster.isSingle) {
          _ensurePhotoPin(cluster.first);
        }
      }

      // 2 — Remove stale clusters
      final stale = _symbolMap.entries
          .where((e) => !targetKeys.contains(e.value.key))
          .map((e) => e.key)
          .toList();
      for (final sym in stale) {
        _symbolMap.remove(sym);
      }
      try {
        await ctrl.removeSymbols(stale);
      } catch (_) {}
    } finally {
      _syncing = false;
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final cluster = _symbolMap[symbol];
    if (cluster == null) return;
    if (cluster.isSingle) {
      _flyToDrop(cluster.first);
    } else {
      _showClusterSheet(cluster.drops);
    }
  }

  void _showClusterSheet(List<DropModel> drops) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClusterSheet(
        drops: drops,
        userPosition: _userPosition,
        onSelect: (m) {
          Navigator.pop(ctx);
          setState(() => _selectedDrop = m);
          _flyToDrop(m);
        },
      ),
    );
  }

  // ─── Location & data ──────────────────────────────────────────────────────

  Future<void> _loadNearby() async {
    final pos = await _initLocation();
    if (!mounted) return;

    if (pos == null) {
      // Niente posizione reale: prima si ripiegava silenziosamente su Roma,
      // mostrando drop "vicino a te" che in realtà erano vicino a Roma.
      // Meglio nessun risultato di uno sbagliato — l'utente può riprovare
      // col bottone di centratura una volta attivato il GPS.
      setState(() {
        _drops = [];
        _dismissedCount = 0;
      });
      EchoToast.show(
        context,
        'Posizione non disponibile. Attiva il GPS per vedere e lasciare drop vicino a te.',
        type: EchoToastType.error,
      );
      return;
    }

    final nearby = await ref
        .read(dropRepositoryProvider)
        .getNearbyDrops(
          lat: pos.latitude,
          lng: pos.longitude,
          visibilities: _selectedVisibilities.map((v) => v.value).toSet(),
        );

    if (!mounted) return;
    setState(() {
      _drops = nearby;
      _dismissedCount = 0;
    });

    if (_mapReady) await _flyToUserAndReveal();
  }

  Future<void> _refreshNearby() async {
    if (!_mapReady) return;
    double lat, lng;
    final camPos = _mapController?.cameraPosition;
    if (camPos != null) {
      lat = camPos.target.latitude;
      lng = camPos.target.longitude;
    } else if (_userPosition != null) {
      lat = _userPosition!.latitude;
      lng = _userPosition!.longitude;
    } else {
      return;
    }
    final nearby = await ref
        .read(dropRepositoryProvider)
        .getNearbyDrops(
          lat: lat,
          lng: lng,
          visibilities: _selectedVisibilities.map((v) => v.value).toSet(),
        );
    if (!mounted) return;
    // Note: _dismissedCount is deliberately NOT reset here — this runs on
    // every camera-idle/pan and provider update, and resetting it would
    // snap the visible card back to the first (nearest) drop even if the
    // user had already swiped past it. The modulo in _currentDrop already
    // keeps the index safely in bounds if the list shrinks.
    setState(() => _drops = nearby);
    await _syncAnnotations();
  }

  Future<void> _onVisibilityToggled(DropVisibility vis) async {
    setState(() {
      if (_selectedVisibilities.contains(vis)) {
        if (_selectedVisibilities.length > 1) {
          _selectedVisibilities = {..._selectedVisibilities}..remove(vis);
        }
      } else {
        _selectedVisibilities = {..._selectedVisibilities, vis};
      }
    });
    if (_mapReady) await _refreshNearby();
  }

  Future<geo.Position?> _initLocation() async {
    try {
      final perm = await PermissionGate.run(() => geo.Geolocator.requestPermission());
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        return null;
      }
      final pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<void> _flyToUserAndReveal() async {
    final ctrl = _mapController;
    final userPos = _userPosition;
    // Senza una posizione reale non si vola più su Roma spacciandola per
    // "qui" — il mirino/i marker restano nascosti finché non c'è un fix GPS
    // vero (vedi _loadNearby e _centerOnUser per i punti di retry).
    if (ctrl == null || userPos == null) return;
    final lat = userPos.latitude;
    final lng = userPos.longitude;

    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(lat, lng), zoom: 15, tilt: 45),
      ),
      duration: const Duration(milliseconds: 3000),
    );

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _showMarkers = true;
      _showCrosshair = true;
    });
    await _syncAnnotations();

    await Future<void>.delayed(const Duration(seconds: 2));
    await _discoverDrop();

    _viewportLoadEnabled = true;

    final pending = _pendingFlyTarget;
    if (pending != null) {
      _pendingFlyTarget = null;
      await _flyToTarget(pending.drop);
    }
  }

  Future<void> _discoverDrop() async {
    if (_dropDiscovered) return;
    setState(() => _dropDiscovered = true);
    await Vibration.vibrate(duration: 80);
    final drop = _currentDrop;
    if (drop != null) await _flyToDrop(drop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTutorialTargets();
    });
  }

  /// Measures the real on-screen position of each guided-tour target so its
  /// arrows point exactly at the actual widgets, not an approximation.
  void _measureTutorialTargets() {
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final targets = <int, Offset>{
      0: Offset(screenSize.width / 2, screenSize.height / 2),
    };
    final keyed = {1: _filterRowKey, 2: _cardAreaKey, 3: _addButtonKey};
    for (final entry in keyed.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        // The drop card area is bottom-aligned, so its true center sits low
        // (close to the FAB buttons) — aim a bit higher, toward its top.
        final anchor = entry.key == 2
            ? Offset(box.size.width / 2, box.size.height * 0.22)
            : box.size.center(Offset.zero);
        targets[entry.key] = box.localToGlobal(anchor);
      }
    }
    if (targets.length == 4) {
      setState(() => _tutorialTargets = targets);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<DropModel> get _sortedByDistance {
    if (_userPosition == null) return _drops;
    final list = List<DropModel>.from(_drops);
    list.sort((a, b) {
      final da = geo.Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        a.latitude,
        a.longitude,
      );
      final db = geo.Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        b.latitude,
        b.longitude,
      );
      return da.compareTo(db);
    });
    return list;
  }

  DropModel? get _currentDrop {
    if (_selectedDrop != null) return _selectedDrop;
    final sorted = _sortedByDistance;
    if (sorted.isEmpty) return null;
    return sorted[_dismissedCount % sorted.length];
  }

  /// The drop that peeks out from behind the current card in the stack.
  DropModel? get _nextDrop {
    final sorted = _sortedByDistance;
    if (sorted.length < 2) return null;
    return sorted[(_dismissedCount + 1) % sorted.length];
  }

  // ─── Swipe-to-dismiss (reel-style, swipe up) ──────────────────────────────

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset < -80 || velocity < -700) {
      _triggerDismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  Future<void> _triggerDismiss() async {
    if (_isDismissing) return;
    setState(() {
      _isDismissing = true;
      _dismissStartOffset = _dragOffset;
    });
    _dismissCtrl.reset();
    await _dismissCtrl.forward();
    if (!mounted) return;
    setState(() {
      _selectedDrop = null;
      _dismissedCount++;
      _dragOffset = 0;
      _isDismissing = false;
    });
    _dismissCtrl.reset();
    final next = _currentDrop;
    if (next != null) await _flyToDrop(next);
  }

  double? _distanceTo(DropModel drop) {
    if (_userPosition == null) return null;
    return geo.Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      drop.latitude,
      drop.longitude,
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _flyToDrop(DropModel drop) async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(drop.latitude, drop.longitude),
          zoom: 16,
          tilt: 45,
        ),
      ),
      duration: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _flyToTarget(DropModel drop) async {
    final ctrl = _mapController;
    if (ctrl == null) return;

    bool needsSync = !_showMarkers;

    if (!_drops.any((m) => m.id == drop.id)) {
      setState(() => _drops = [..._drops, drop]);
      needsSync = true;
    }

    if (!_showMarkers) {
      setState(() {
        _showMarkers = true;
        _showCrosshair = true;
      });
    }

    if (needsSync) await _syncAnnotations();

    setState(() {
      _dropDiscovered = true;
      _selectedDrop = drop;
    });

    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(drop.latitude, drop.longitude),
          zoom: 16,
          tilt: 45,
        ),
      ),
      duration: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _createFromMap() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    if (_userPosition == null) {
      // Senza un fix GPS reale il centro mappa può ancora essere il default
      // (Roma): meglio bloccare la creazione che salvare un drop lì senza
      // che l'utente se ne accorga.
      EchoToast.show(
        context,
        'Posizione non disponibile. Attiva il GPS per lasciare un drop qui.',
        type: EchoToastType.error,
      );
      return;
    }
    final pos = ctrl.cameraPosition;
    if (pos == null) return;
    ref
        .read(mapCreateLocationProvider.notifier)
        .set(pos.target.latitude, pos.target.longitude);
    ref.read(shellIndexProvider.notifier).setIndex(2);
  }

  Future<void> _centerOnUser() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {
      pos = _userPosition;
    }
    if (pos == null) {
      if (mounted) {
        EchoToast.show(
          context,
          'Posizione non disponibile. Controlla che il GPS sia attivo.',
          type: EchoToastType.error,
        );
      }
      return;
    }
    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16,
          tilt: 45,
        ),
      ),
      duration: const Duration(milliseconds: 900),
    );
    if (!mounted) return;
    // Se il fix iniziale era fallito, questo è il punto di recupero: ora che
    // abbiamo una posizione vera, sblocchiamo mirino/marker/creazione.
    if (!_showMarkers || !_showCrosshair) {
      setState(() {
        _showMarkers = true;
        _showCrosshair = true;
      });
      await _syncAnnotations();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(discoverProvider, (_, _) {
      if (_mapReady) _refreshNearby();
    });

    ref.listen<MapFlyTarget?>(mapFlyTargetProvider, (_, target) {
      if (target == null) return;
      ref.read(mapFlyTargetProvider.notifier).clear();
      if (_mapReady) {
        _flyToTarget(target.drop);
      } else {
        _pendingFlyTarget = target;
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final currentDrop = _currentDrop;
    final currentDist = currentDrop != null ? _distanceTo(currentDrop) : null;

    if (!isOnline) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF100F1C),
                          Color(0xFF181528),
                          Color(0xFF100E1A),
                        ]
                      : const [
                          Color(0xFFF3F1FC),
                          Color(0xFFE9E6F7),
                          Color(0xFFF2F0FB),
                        ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(
                  'mingle.',
                  style: AppTextStyles.logo(
                    context,
                  ).copyWith(fontSize: 18, color: AppColors.accent),
                ),
              ),
            ),
            const OfflinePlaceholder(
              message:
                  'La mappa non è disponibile offline.\nTorna online per esplorare i drop vicini.',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          MapLibreMap(
            key: const ValueKey('mapWidget'),
            styleString: isDark
                ? AppConstants.maptilerDarkStyle
                : AppConstants.maptilerLightStyle,
            initialCameraPosition: const CameraPosition(
              target: LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
              zoom: 13,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              controller.onSymbolTapped.add(_onSymbolTapped);
            },
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: () {
              if (_viewportLoadEnabled && _showMarkers && mounted) {
                _refreshNearby();
              }
            },
            myLocationEnabled: true,
            myLocationRenderMode: MyLocationRenderMode.normal,
            compassEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            tiltGesturesEnabled: true,
          ),

          // ── Crosshair ──────────────────────────────────────────────────────
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                opacity: _showCrosshair ? 1.0 : 0.0,
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(painter: _CrosshairPainter()),
                ),
              ),
            ),
          ),

          // ── HUD ────────────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 98),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'mingle.',
                    style: AppTextStyles.logo(
                      context,
                    ).copyWith(fontSize: 30, color: AppColors.accent),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _drops.isEmpty
                          ? 'Cerco drop vicini…'
                          : '${_drops.length} drop ${_drops.length == 1 ? 'vicino' : 'vicini'}',
                      key: ValueKey(_drops.length),
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _filterRowKey,
                    child: _MapFilterRow(
                      selected: _selectedVisibilities,
                      onToggle: _onVisibilityToggled,
                    ),
                  ),
                  const Spacer(),

                  // Drop card stack + FAB
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        key: _cardAreaKey,
                        child: currentDrop != null
                            ? AnimatedSlide(
                                duration: const Duration(milliseconds: 900),
                                offset: _dropDiscovered
                                    ? Offset.zero
                                    : const Offset(0, 1),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 900),
                                  opacity: _dropDiscovered ? 1 : 0,
                                  child: SizedBox(
                                    height: 195,
                                    child: AnimatedBuilder(
                                      animation: _dismissCtrl,
                                      builder: (context, _) {
                                        // How far the top card has travelled
                                        // toward being dismissed, 0 → 1.
                                        final progress = _isDismissing
                                            ? _dismissCtrl.value
                                            : (-_dragOffset / 160).clamp(
                                                0.0,
                                                1.0,
                                              );

                                        final dy = _isDismissing
                                            ? _dismissStartOffset -
                                                  _dismissCtrl.value * 160
                                            : _dragOffset;
                                        final topOpacity = _isDismissing
                                            ? 1 - _dismissCtrl.value
                                            : 1.0;

                                        return Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Peek of the next card, easing
                                            // softly into place as the top
                                            // card leaves.
                                            if (_nextDrop != null)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: Transform.translate(
                                                    offset: Offset(
                                                      0,
                                                      ui.lerpDouble(
                                                        14,
                                                        0,
                                                        progress,
                                                      )!,
                                                    ),
                                                    child: Transform.scale(
                                                      scale: ui.lerpDouble(
                                                        0.94,
                                                        1.0,
                                                        progress,
                                                      )!,
                                                      child: Opacity(
                                                        opacity: ui.lerpDouble(
                                                          0.4,
                                                          1.0,
                                                          progress,
                                                        )!,
                                                        child: _DropPreviewCard(
                                                          drop: _nextDrop!,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            // Active, draggable card on top
                                            Opacity(
                                              opacity: topOpacity,
                                              child: Transform.translate(
                                                offset: Offset(0, dy),
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      _flyToDrop(currentDrop),
                                                  onVerticalDragUpdate:
                                                      _onDragUpdate,
                                                  onVerticalDragEnd: _onDragEnd,
                                                  child: _DropPreviewCard(
                                                    drop: currentDrop,
                                                    distance: currentDist,
                                                    formatDistance:
                                                        _formatDistance,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MapCircleButton(
                            icon: Icons.my_location_rounded,
                            onTap: _centerOnUser,
                          ),
                          const SizedBox(height: 10),
                          KeyedSubtree(
                            key: _addButtonKey,
                            child: _MapCircleButton(
                              icon: Icons.add,
                              onTap: _createFromMap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── First-run guided tour ────────────────────────────────────────
          if (_mapReady &&
              _tutorialTargets != null &&
              ref.watch(mapTutorialProvider).asData?.value == false)
            MapTutorialOverlay(
              targets: _tutorialTargets!,
              onDone: () => ref.read(mapTutorialProvider.notifier).markSeen(),
            ),
        ],
      ),
    );
  }
}

// ─── Crosshair ────────────────────────────────────────────────────────────────

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, ui.Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    const ringRadius = 5.0;
    const armLength = 10.0;
    const gap = 8.0;
    const strokeWidth = 1.2;

    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = strokeWidth + 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.5);

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final arms = [
      [center.translate(0, -gap), center.translate(0, -(gap + armLength))],
      [center.translate(0, gap), center.translate(0, gap + armLength)],
      [center.translate(-gap, 0), center.translate(-(gap + armLength), 0)],
      [center.translate(gap, 0), center.translate(gap + armLength, 0)],
    ];

    for (final arm in arms) {
      canvas.drawLine(arm[0], arm[1], shadowPaint);
    }
    for (final arm in arms) {
      canvas.drawLine(arm[0], arm[1], paint);
    }

    canvas.drawCircle(center, ringRadius, shadowPaint);
    canvas.drawCircle(center, ringRadius, paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter _) => false;
}

// ─── Drop preview card (Tinder-style stack on the map) ────────────────────────

class _DropPreviewCard extends StatelessWidget {
  const _DropPreviewCard({
    required this.drop,
    this.distance,
    this.formatDistance,
  });

  final DropModel drop;
  final double? distance;
  final String Function(double)? formatDistance;

  @override
  Widget build(BuildContext context) {
    final hasImage = drop.imageUrl != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: photo fills the whole card, reel-style ───────────
          if (hasImage)
            CachedNetworkImage(
              imageUrl: drop.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => _ReelFallbackBg(mood: drop.mood),
              errorWidget: (_, _, _) => _ReelFallbackBg(mood: drop.mood),
            )
          else
            _ReelFallbackBg(mood: drop.mood),

          // ── Bottom gradient for text legibility ───────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),

          // ── Minimal content: mood, distance, one-line description ────────
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(drop.mood.icon, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      drop.mood.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (distance != null && formatDistance != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.near_me_outlined,
                            size: 11,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            formatDistance!(distance!),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  drop.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Map filter row ───────────────────────────────────────────────────────────

class _MapFilterRow extends StatelessWidget {
  const _MapFilterRow({required this.selected, required this.onToggle});
  final Set<DropVisibility> selected;
  final void Function(DropVisibility) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MapFilterChip(
          label: 'Pubblici',
          icon: Icons.public_outlined,
          selected: selected.contains(DropVisibility.public),
          onTap: () => onToggle(DropVisibility.public),
        ),
        const SizedBox(width: 8),
        _MapFilterChip(
          label: 'Cerchia',
          icon: Icons.people_outline,
          selected: selected.contains(DropVisibility.circle),
          onTap: () => onToggle(DropVisibility.circle),
        ),
        const SizedBox(width: 8),
        _MapFilterChip(
          label: 'Privati',
          icon: Icons.lock_outline,
          selected: selected.contains(DropVisibility.private),
          onTap: () => onToggle(DropVisibility.private),
        ),
      ],
    );
  }
}

class _MapFilterChip extends StatelessWidget {
  const _MapFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.72))
              : Colors.black.withValues(alpha: isDark ? 0.30 : 0.50),
          border: Border.all(
            color: selected
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.50)
                      : Colors.black.withValues(alpha: 0.60))
                : (isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.28)),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Map circle button (locate / add) ────────────────────────────────────────

class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ─── Cluster bottom sheet ─────────────────────────────────────────────────────

class _ClusterSheet extends StatefulWidget {
  const _ClusterSheet({
    required this.drops,
    required this.onSelect,
    this.userPosition,
  });

  final List<DropModel> drops;
  final void Function(DropModel) onSelect;
  final geo.Position? userPosition;

  @override
  State<_ClusterSheet> createState() => _ClusterSheetState();
}

class _ClusterSheetState extends State<_ClusterSheet> {
  late final PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF131720) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  '${widget.drops.length} drop ${widget.drops.length == 1 ? 'qui vicino' : 'qui vicini'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_currentPage + 1} / ${widget.drops.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Carousel
          SizedBox(
            height: 260,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.drops.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final m = widget.drops[i];
                double? dist;
                if (widget.userPosition != null) {
                  dist = geo.Geolocator.distanceBetween(
                    widget.userPosition!.latitude,
                    widget.userPosition!.longitude,
                    m.latitude,
                    m.longitude,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _ClusterCard(
                    drop: m,
                    distance: dist != null ? _formatDistance(dist) : null,
                    onTap: () => widget.onSelect(m),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Page dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.drops.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: active
                      ? const Color(0xFF33CCBD)
                      : Colors.grey.withValues(alpha: 0.35),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({required this.drop, required this.onTap, this.distance});

  final DropModel drop;
  final VoidCallback onTap;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final hasImage = drop.imageUrl != null;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background: photo or mood gradient ────────────────────────
            if (hasImage)
              CachedNetworkImage(
                imageUrl: drop.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => _MoodGradientBg(mood: drop.mood),
                errorWidget: (_, _, _) => _MoodGradientBg(mood: drop.mood),
              )
            else
              _MoodGradientBg(mood: drop.mood),

            // ── Bottom gradient overlay ────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mood badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSecondary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accentSecondary.withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.accentSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          drop.mood.label,
                          style: const TextStyle(
                            color: AppColors.accentSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Description
                  Text(
                    drop.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Meta row: author + distance + counts
                  Row(
                    children: [
                      if (drop.author?.displayName != null) ...[
                        Text(
                          '@${drop.author!.displayName}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (distance != null)
                        Text(
                          distance!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      const Spacer(),
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${drop.likesCount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${drop.commentsCount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodGradientBg extends StatelessWidget {
  const _MoodGradientBg({required this.mood});
  final DropMood mood;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.accentSecondary, width: 2),
      ),
      child: Center(
        child: Icon(mood.icon, size: 44, color: AppColors.accentSecondary),
      ),
    );
  }
}

/// No-photo fallback for the reel-style drop preview card — a full-bleed
/// orange gradient instead of white, so it reads as part of the photo card
/// rather than a blank/empty tile.
class _ReelFallbackBg extends StatelessWidget {
  const _ReelFallbackBg({required this.mood});
  final DropMood mood;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentSecondary, Color(0xFF7A3E00)],
        ),
      ),
      child: Center(
        child: Icon(
          mood.icon,
          size: 44,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
