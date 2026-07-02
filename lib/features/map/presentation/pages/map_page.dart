import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:echo/features/memory/providers/memory_provider.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:vibration/vibration.dart';

// ─── Cluster ──────────────────────────────────────────────────────────────────

class _MemoryCluster {
  final List<MemoryModel> memories;
  final double lat;
  final double lng;

  const _MemoryCluster({required this.memories, required this.lat, required this.lng});

  bool get isSingle => memories.length == 1;
  MemoryModel get first => memories.first;

  String get key => (memories.map((m) => m.id).toList()..sort()).join(',');
}

List<_MemoryCluster> _buildClusters(List<MemoryModel> memories, {double radiusMeters = 20.0}) {
  final result = <_MemoryCluster>[];
  final assigned = <String>{};

  for (final m in memories) {
    if (assigned.contains(m.id)) continue;
    final group = <MemoryModel>[m];
    assigned.add(m.id);

    for (final other in memories) {
      if (assigned.contains(other.id)) continue;
      final dist = geo.Geolocator.distanceBetween(
        m.latitude, m.longitude, other.latitude, other.longitude,
      );
      if (dist <= radiusMeters) {
        group.add(other);
        assigned.add(other.id);
      }
    }

    final avgLat = group.map((e) => e.latitude).reduce((a, b) => a + b) / group.length;
    final avgLng = group.map((e) => e.longitude).reduce((a, b) => a + b) / group.length;
    result.add(_MemoryCluster(memories: group, lat: avgLat, lng: avgLng));
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

  // symbol → cluster (single or multi memory)
  final Map<Symbol, _MemoryCluster> _symbolMap = {};

  // mood → pre-rendered PNG bytes (rendered once, re-registered on style reload)
  final Map<MemoryMood, Uint8List> _moodImages = {};

  // count → pre-rendered cluster badge PNG bytes
  final Map<int, Uint8List> _clusterImages = {};

  Set<MemoryVisibility> _selectedVisibilities = {MemoryVisibility.public};

  bool _showMarkers = false;
  bool _showCrosshair = false;
  bool _memoryDiscovered = false;
  bool _mapReady = false;
  bool _viewportLoadEnabled = false;
  geo.Position? _userPosition;
  List<MemoryModel> _memories = [];
  MemoryModel? _selectedMemory;
  MapFlyTarget? _pendingFlyTarget;

  // tracks whether the initial fly-to-user has happened (avoids re-flying on style reload)
  bool _initialRevealDone = false;

  // prevents concurrent _syncAnnotations calls from interleaving
  bool _syncing = false;

  // swipe-to-dismiss state
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

  // ─── Mood image rendering ─────────────────────────────────────────────────

  Future<void> _preRenderMoodImages() async {
    for (final mood in MemoryMood.values) {
      _moodImages[mood] = await _renderMoodDot(mood);
    }
  }

  Future<Uint8List> _renderMoodDot(MemoryMood mood) async {
    const double size = 64.0;
    const double r = 13.0;
    final color = mood.color;
    const center = Offset(size / 2, size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Outer glow
    canvas.drawCircle(
      center,
      r + 9,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
    );
    // Drop shadow
    canvas.drawCircle(
      center + const Offset(0, 2.5),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    // Spherical dot with radial gradient
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(center.dx - r * 0.3, center.dy - r * 0.35),
          r * 0.88,
          [
            Color.lerp(Colors.white, color, 0.38)!,
            color,
            Color.lerp(color, Colors.black, 0.22)!,
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ─── Cluster image rendering ──────────────────────────────────────────────

  Future<Uint8List> _renderClusterDot(int count) async {
    const double size = 100.0;
    const double r = 30.0;
    const color = Color(0xFF33CCBD);
    const center = Offset(size / 2, size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Outer glow
    canvas.drawCircle(
      center, r + 12,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12),
    );
    // Drop shadow
    canvas.drawCircle(
      center + const Offset(0, 3), r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    // Main circle
    canvas.drawCircle(center, r, Paint()..color = color);

    // Count label
    final label = count > 9 ? '9+' : '$count';
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 34),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontSize: 34,
        fontWeight: ui.FontWeight.bold,
      ))
      ..addText(label);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(
      paragraph,
      Offset(0, center.dy - paragraph.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
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

    _mapReady = true;
    if (!_initialRevealDone) {
      _initialRevealDone = true;
      if (mounted && _userPosition != null) await _flyToUserAndReveal();
    } else if (_showMarkers) {
      await _syncAnnotations();
    }
  }

  // ─── Annotation sync ──────────────────────────────────────────────────────

  Future<void> _syncAnnotations() async {
    final ctrl = _mapController;
    if (ctrl == null || !_showMarkers || _syncing) return;
    _syncing = true;

    try {
      final clusters = _buildClusters(_memories);
      final targetKeys = clusters.map((c) => c.key).toSet();
      final shownKeys = _symbolMap.values.map((c) => c.key).toSet();

      // 1 — Add new clusters FIRST so there's never a gap on screen
      for (final cluster in clusters) {
        if (shownKeys.contains(cluster.key)) continue;

        final String imageKey;
        if (cluster.isSingle) {
          if (_moodImages[cluster.first.mood] == null) continue;
          imageKey = 'mood-${cluster.first.mood.name}';
        } else {
          final count = cluster.memories.length;
          final cacheKey = 'cluster-$count';
          if (!_clusterImages.containsKey(count)) {
            final bytes = await _renderClusterDot(count);
            _clusterImages[count] = bytes;
            try { await ctrl.addImage(cacheKey, bytes); } catch (_) {}
          }
          imageKey = cacheKey;
        }

        try {
          final sym = await ctrl.addSymbol(SymbolOptions(
            geometry: LatLng(cluster.lat, cluster.lng),
            iconImage: imageKey,
            iconSize: cluster.isSingle ? 1.0 : 1.15,
            iconAnchor: 'center',
          ));
          _symbolMap[sym] = cluster;
        } catch (_) {}
      }

      // 2 — Remove stale clusters
      final stale = _symbolMap.entries
          .where((e) => !targetKeys.contains(e.value.key))
          .map((e) => e.key)
          .toList();
      for (final sym in stale) { _symbolMap.remove(sym); }
      try { await ctrl.removeSymbols(stale); } catch (_) {}
    } finally {
      _syncing = false;
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final cluster = _symbolMap[symbol];
    if (cluster == null) return;
    if (cluster.isSingle) {
      _flyToMemory(cluster.first);
    } else {
      _showClusterSheet(cluster.memories);
    }
  }

  void _showClusterSheet(List<MemoryModel> memories) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClusterSheet(
        memories: memories,
        userPosition: _userPosition,
        onSelect: (m) {
          Navigator.pop(ctx);
          setState(() => _selectedMemory = m);
          _flyToMemory(m);
        },
      ),
    );
  }

  // ─── Location & data ──────────────────────────────────────────────────────

  Future<void> _loadNearby() async {
    final pos = await _initLocation();
    if (!mounted) return;
    final lat = pos?.latitude ?? AppConstants.defaultLat;
    final lng = pos?.longitude ?? AppConstants.defaultLng;

    final nearby = await ref.read(memoryRepositoryProvider).getNearbyMemories(
      lat: lat,
      lng: lng,
      visibilities: _selectedVisibilities.map((v) => v.value).toSet(),
    );

    if (!mounted) return;
    setState(() {
      _memories = nearby;
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
    final nearby = await ref.read(memoryRepositoryProvider).getNearbyMemories(
      lat: lat,
      lng: lng,
      visibilities: _selectedVisibilities.map((v) => v.value).toSet(),
    );
    if (!mounted) return;
    setState(() {
      _memories = nearby;
      _dismissedCount = 0;
    });
    await _syncAnnotations();
  }

  Future<void> _onVisibilityToggled(MemoryVisibility vis) async {
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
      final perm = await geo.Geolocator.requestPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) { return null; }
      final pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<void> _flyToUserAndReveal() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final lat = _userPosition?.latitude ?? AppConstants.defaultLat;
    final lng = _userPosition?.longitude ?? AppConstants.defaultLng;

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
    await _discoverMemory();

    _viewportLoadEnabled = true;

    final pending = _pendingFlyTarget;
    if (pending != null) {
      _pendingFlyTarget = null;
      await _flyToTarget(pending.memory);
    }
  }

  Future<void> _discoverMemory() async {
    if (_memoryDiscovered) return;
    setState(() => _memoryDiscovered = true);
    await Vibration.vibrate(duration: 80);
    final memory = _currentMemory;
    if (memory != null) await _flyToMemory(memory);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<MemoryModel> get _sortedByDistance {
    if (_userPosition == null) return _memories;
    final list = List<MemoryModel>.from(_memories);
    list.sort((a, b) {
      final da = geo.Geolocator.distanceBetween(
        _userPosition!.latitude, _userPosition!.longitude,
        a.latitude, a.longitude,
      );
      final db = geo.Geolocator.distanceBetween(
        _userPosition!.latitude, _userPosition!.longitude,
        b.latitude, b.longitude,
      );
      return da.compareTo(db);
    });
    return list;
  }

  MemoryModel? get _currentMemory {
    if (_selectedMemory != null) return _selectedMemory;
    final sorted = _sortedByDistance;
    if (sorted.isEmpty) return null;
    return sorted[_dismissedCount % sorted.length];
  }

  // ─── Swipe-to-dismiss ─────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset > 18) _dragOffset = 18;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset < -60 || velocity < -600) {
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
      _selectedMemory = null;
      _dismissedCount++;
      _dragOffset = 0;
      _isDismissing = false;
    });
    _dismissCtrl.reset();
    final next = _currentMemory;
    if (next != null) await _flyToMemory(next);
  }

  double? _distanceTo(MemoryModel memory) {
    if (_userPosition == null) return null;
    return geo.Geolocator.distanceBetween(
      _userPosition!.latitude, _userPosition!.longitude,
      memory.latitude, memory.longitude,
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _flyToMemory(MemoryModel memory) async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(memory.latitude, memory.longitude),
          zoom: 16,
          tilt: 45,
        ),
      ),
      duration: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _flyToTarget(MemoryModel memory) async {
    final ctrl = _mapController;
    if (ctrl == null) return;

    bool needsSync = !_showMarkers;

    if (!_memories.any((m) => m.id == memory.id)) {
      setState(() => _memories = [..._memories, memory]);
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
      _memoryDiscovered = true;
      _selectedMemory = memory;
    });

    await ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(memory.latitude, memory.longitude),
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
    final pos = ctrl.cameraPosition;
    if (pos == null) return;
    ref.read(mapCreateLocationProvider.notifier).set(
      pos.target.latitude,
      pos.target.longitude,
    );
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
    if (pos == null) return;
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
        _flyToTarget(target.memory);
      } else {
        _pendingFlyTarget = target;
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final currentMemory = _currentMemory;
    final currentDist =
        currentMemory != null ? _distanceTo(currentMemory) : null;

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
                      ? const [Color(0xFF100F1C), Color(0xFF181528), Color(0xFF100E1A)]
                      : const [Color(0xFFF3F1FC), Color(0xFFE9E6F7), Color(0xFFF2F0FB)],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text('Echo.', style: AppTextStyles.displayLarge(context)),
              ),
            ),
            const OfflinePlaceholder(
              message: 'La mappa non è disponibile offline.\nTorna online per esplorare i ricordi vicini.',
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
            styleString: AppConstants.maptilerLightStyle,
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
                  Text('Echo.', style: AppTextStyles.displayLarge(context)),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _memories.isEmpty
                          ? 'Cerco ricordi vicini…'
                          : '${_memories.length} ${_memories.length == 1 ? 'ricordo' : 'ricordi'} vicini',
                      key: ValueKey(_memories.length),
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MapFilterRow(
                    selected: _selectedVisibilities,
                    onToggle: _onVisibilityToggled,
                  ),
                  const Spacer(),

                  // Memory card + FAB
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: currentMemory != null
                            ? AnimatedSlide(
                                duration: const Duration(milliseconds: 900),
                                offset: _memoryDiscovered
                                    ? Offset.zero
                                    : const Offset(0, 1),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 900),
                                  opacity: _memoryDiscovered ? 1 : 0,
                                  child: AnimatedBuilder(
                                    animation: _dismissCtrl,
                                    builder: (context, _) {
                                      final dy = _isDismissing
                                          ? _dismissStartOffset +
                                              _dismissCtrl.value *
                                                  (-300 - _dismissStartOffset)
                                          : _dragOffset;
                                      final opacity = _isDismissing
                                          ? (1.0 - _dismissCtrl.value)
                                              .clamp(0.0, 1.0)
                                          : (_dragOffset < 0
                                                  ? 1.0 + _dragOffset / 120
                                                  : 1.0)
                                              .clamp(0.0, 1.0);
                                      return Transform.translate(
                                        offset: Offset(0, dy),
                                        child: Opacity(
                                          opacity: opacity,
                                          child: GestureDetector(
                                            onTap: () => _flyToMemory(currentMemory),
                                            onVerticalDragUpdate: _onDragUpdate,
                                            onVerticalDragEnd: _onDragEnd,
                                            child: GlassCard(
                                              child: Padding(
                                                padding: const EdgeInsets.all(20),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        _MoodDot(mood: currentMemory.mood),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          currentMemory.mood.label,
                                                          style: AppTextStyles
                                                              .bodySecondary(context)
                                                              .copyWith(
                                                            color: currentMemory.mood.color,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        if (currentDist != null)
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                Icons.near_me_outlined,
                                                                size: 11,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurface
                                                                    .withValues(alpha: 0.4),
                                                              ),
                                                              const SizedBox(width: 3),
                                                              Text(
                                                                _formatDistance(currentDist),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Theme.of(context)
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withValues(alpha: 0.4),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      currentMemory.description,
                                                      style: AppTextStyles.headline(context),
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (currentMemory.aiCaption != null) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        currentMemory.aiCaption!,
                                                        style: AppTextStyles
                                                            .bodySecondary(context)
                                                            .copyWith(
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
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
                          _MapCircleButton(
                            icon: Icons.add,
                            onTap: _createFromMap,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

    for (final arm in arms) { canvas.drawLine(arm[0], arm[1], shadowPaint); }
    for (final arm in arms) { canvas.drawLine(arm[0], arm[1], paint); }

    canvas.drawCircle(center, ringRadius, shadowPaint);
    canvas.drawCircle(center, ringRadius, paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter _) => false;
}

// ─── Mood dot (bottom card only) ─────────────────────────────────────────────

class _MoodDot extends StatelessWidget {
  const _MoodDot({required this.mood});
  final MemoryMood mood;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: mood.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: mood.color.withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ─── Map filter row ───────────────────────────────────────────────────────────

class _MapFilterRow extends StatelessWidget {
  const _MapFilterRow({required this.selected, required this.onToggle});
  final Set<MemoryVisibility> selected;
  final void Function(MemoryVisibility) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MapFilterChip(
          label: 'Pubblici',
          icon: Icons.public_outlined,
          selected: selected.contains(MemoryVisibility.public),
          onTap: () => onToggle(MemoryVisibility.public),
        ),
        const SizedBox(width: 8),
        _MapFilterChip(
          label: 'Cerchia',
          icon: Icons.people_outline,
          selected: selected.contains(MemoryVisibility.circle),
          onTap: () => onToggle(MemoryVisibility.circle),
        ),
        const SizedBox(width: 8),
        _MapFilterChip(
          label: 'Privati',
          icon: Icons.lock_outline,
          selected: selected.contains(MemoryVisibility.private),
          onTap: () => onToggle(MemoryVisibility.private),
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
            Icon(icon, size: 13, color: selected ? Colors.white : Colors.white54),
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
    required this.memories,
    required this.onSelect,
    this.userPosition,
  });

  final List<MemoryModel> memories;
  final void Function(MemoryModel) onSelect;
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
                  '${widget.memories.length} ricordi qui vicino',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_currentPage + 1} / ${widget.memories.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
              itemCount: widget.memories.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final m = widget.memories[i];
                double? dist;
                if (widget.userPosition != null) {
                  dist = geo.Geolocator.distanceBetween(
                    widget.userPosition!.latitude, widget.userPosition!.longitude,
                    m.latitude, m.longitude,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _ClusterCard(
                    memory: m,
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
            children: List.generate(widget.memories.length, (i) {
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
  const _ClusterCard({
    required this.memory,
    required this.onTap,
    this.distance,
  });

  final MemoryModel memory;
  final VoidCallback onTap;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final hasImage = memory.imageUrl != null;

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
                imageUrl: memory.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => _MoodGradientBg(mood: memory.mood),
                errorWidget: (_, _, _) => _MoodGradientBg(mood: memory.mood),
              )
            else
              _MoodGradientBg(mood: memory.mood),

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
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: memory.mood.color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: memory.mood.color.withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: memory.mood.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          memory.mood.label,
                          style: TextStyle(
                            color: memory.mood.color,
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
                    memory.description,
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
                      if (memory.author?.displayName != null) ...[
                        Text(
                          '@${memory.author!.displayName}',
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
                      Icon(Icons.favorite_border_rounded, size: 13, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 3),
                      Text(
                        '${memory.likesCount}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.chat_bubble_outline_rounded, size: 13, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 3),
                      Text(
                        '${memory.commentsCount}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
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
  final MemoryMood mood;

  @override
  Widget build(BuildContext context) {
    final color = mood.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.black, 0.3)!,
            Color.lerp(color, Colors.black, 0.6)!,
          ],
        ),
      ),
      child: Center(
        child: Text(
          mood.emoji,
          style: const TextStyle(fontSize: 52),
        ),
      ),
    );
  }
}
