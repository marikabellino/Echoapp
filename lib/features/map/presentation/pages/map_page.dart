import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:vibration/vibration.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with SingleTickerProviderStateMixin {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;

  // annotation.id → memory (for click handling)
  final Map<String, MemoryModel> _annotationMap = {};

  // mood → pre-rendered PNG bytes
  final Map<MemoryMood, Uint8List> _moodImages = {};

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

  // ─── Mood image rendering ─────────────────────────────────────────────────────

  Future<void> _preRenderMoodImages() async {
    for (final mood in MemoryMood.values) {
      _moodImages[mood] = await _renderMoodDot(mood);
    }
  }

  Future<Uint8List> _renderMoodDot(MemoryMood mood) async {
    const double size = 64.0;
    const double r = 13.0; // dot radius
    final color = mood.color;
    const center = Offset(size / 2, size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // 1 · Outer glow
    canvas.drawCircle(
      center,
      r + 9,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
    );

    // 2 · Drop shadow
    canvas.drawCircle(
      center + const Offset(0, 2.5),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );

    // 3 · Spherical dot with radial gradient
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

  Future<Uint8List> _renderLocationPuck() async {
    const double size = 60.0;
    const double r = 11.0;
    const center = Offset(size / 2, size / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Drop shadow
    canvas.drawCircle(
      center + const Offset(0, 2.5),
      r + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.40)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );

    // Outer dark ring (contrast border)
    canvas.drawCircle(
      center,
      r + 2.5,
      Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: 0.85),
    );

    // White fill
    canvas.drawCircle(center, r, Paint()..color = Colors.white);

    // Inner center dot (accent)
    canvas.drawCircle(
      center,
      4.0,
      Paint()..color = const Color(0xFF3A7BD5),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ─── Annotation sync ──────────────────────────────────────────────────────────

  Future<void> _syncAnnotations() async {
    final mgr = _annotationManager;
    if (mgr == null || !_showMarkers) return;

    await mgr.deleteAll();
    _annotationMap.clear();

    for (final memory in _memories) {
      final image = _moodImages[memory.mood];
      if (image == null) continue;
      try {
        final ann = await mgr.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(memory.longitude, memory.latitude),
            ),
            image: image,
            iconSize: 1.0,
            iconAnchor: IconAnchor.CENTER,
          ),
        );
        _annotationMap[ann.id] = memory;
      } catch (_) {}
    }
  }

  // ─── Location & data ──────────────────────────────────────────────────────────

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
    setState(() { _memories = nearby; _dismissedCount = 0; });

    if (_mapReady) await _flyToUserAndReveal();
  }

  Future<void> _refreshNearby() async {
    if (!_mapReady) return;
    double lat, lng;
    if (_mapboxMap != null) {
      final cam = await _mapboxMap!.getCameraState();
      lat = cam.center.coordinates.lat.toDouble();
      lng = cam.center.coordinates.lng.toDouble();
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
    setState(() { _memories = nearby; _dismissedCount = 0; });
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
    if (_mapboxMap == null) return;
    final lat = _userPosition?.latitude ?? AppConstants.defaultLat;
    final lng = _userPosition?.longitude ?? AppConstants.defaultLng;

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 15,
        pitch: 45,
      ),
      MapAnimationOptions(duration: 3000),
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

  // ─── Helpers ──────────────────────────────────────────────────────────────────

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

  // ─── Swipe-to-dismiss ─────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset > 18) _dragOffset = 18; // piccolo wiggle verso il basso
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
      _userPosition!.latitude,
      _userPosition!.longitude,
      memory.latitude,
      memory.longitude,
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _flyToMemory(MemoryModel memory) async {
    if (_mapboxMap == null) return;
    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(memory.longitude, memory.latitude)),
        zoom: 16,
        pitch: 45,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  Future<void> _flyToTarget(MemoryModel memory) async {
    if (_mapboxMap == null) return;

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

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(memory.longitude, memory.latitude)),
        zoom: 16,
        pitch: 45,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  Future<void> _createFromMap() async {
    if (_mapboxMap == null) return;
    final cam = await _mapboxMap!.getCameraState();
    final coords = cam.center.coordinates;
    ref.read(mapCreateLocationProvider.notifier).set(
          coords.lat.toDouble(),
          coords.lng.toDouble(),
        );
    ref.read(shellIndexProvider.notifier).setIndex(2);
  }

  Future<void> _centerOnUser() async {
    if (_mapboxMap == null) return;
    geo.Position? pos;
    try {
      pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {
      pos = _userPosition;
    }
    if (pos == null) return;
    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(pos.longitude, pos.latitude)),
        zoom: 16,
        pitch: 45,
      ),
      MapAnimationOptions(duration: 900),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Refresh native annotations whenever a memory is created or deleted
    ref.listen(discoverProvider, (_, _) {
      if (_mapReady && _userPosition != null) _refreshNearby();
    });

    // Fly to a memory tapped from Scopri
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
      extendBody: true,
      body: Stack(
        children: [
          // ── Map (markers are native Mapbox annotations — no Flutter overlay) ──
          MapWidget(
            key: const ValueKey('mapWidget'),
            styleUri: isDark ? MapboxStyles.DARK : MapboxStyles.LIGHT,
            onMapIdleListener: (_) {
              if (_viewportLoadEnabled && _showMarkers && mounted) {
                _refreshNearby();
              }
            },
            onMapCreated: (controller) async {
              _mapboxMap = controller;

              await controller.setCamera(CameraOptions(
                center: Point(
                  coordinates: Position(
                    AppConstants.defaultLng,
                    AppConstants.defaultLat,
                  ),
                ),
                zoom: 13,
              ));

              final puckBytes = await _renderLocationPuck();
              await controller.location.updateSettings(
                LocationComponentSettings(
                  enabled: true,
                  pulsingEnabled: true,
                  pulsingColor: Colors.white.toARGB32(),
                  pulsingMaxRadius: 70.0,
                  locationPuck: LocationPuck(
                    locationPuck2D: LocationPuck2D(topImage: puckBytes),
                  ),
                ),
              );
              controller.logo.updateSettings(LogoSettings(enabled: false));
              controller.attribution.updateSettings(
                AttributionSettings(enabled: false),
              );
              controller.scaleBar
                  .updateSettings(ScaleBarSettings(enabled: false));
              controller.compass
                  .updateSettings(CompassSettings(enabled: false));

              // Native annotation manager — dots stay fixed to coordinates
              _annotationManager = await controller.annotations
                  .createPointAnnotationManager();
              // ignore: deprecated_member_use
              _annotationManager!.addOnPointAnnotationClickListener(
                _AnnotationClickListener(
                  annotationMap: _annotationMap,
                  onTap: _flyToMemory,
                ),
              );

              // Pre-render one PNG per mood (done once, then cached)
              await _preRenderMoodImages();

              _mapReady = true;
              if (_userPosition != null) await _flyToUserAndReveal();
            },
          ),

          // ── Crosshair ────────────────────────────────────────────────────────
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

          // ── HUD ──────────────────────────────────────────────────────────────
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

                  // Memory card + create-here FAB
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
                                                  ? 1.0 +
                                                      _dragOffset / 120
                                                  : 1.0)
                                              .clamp(0.0, 1.0);
                                      return Transform.translate(
                                        offset: Offset(0, dy),
                                        child: Opacity(
                                          opacity: opacity,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _flyToMemory(currentMemory),
                                            onVerticalDragUpdate:
                                                _onDragUpdate,
                                            onVerticalDragEnd: _onDragEnd,
                                            child: GlassCard(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        _MoodDot(
                                                            mood: currentMemory
                                                                .mood),
                                                        const SizedBox(
                                                            width: 8),
                                                        Text(
                                                          currentMemory
                                                              .mood.label,
                                                          style: AppTextStyles
                                                              .bodySecondary(
                                                                  context)
                                                              .copyWith(
                                                            color: currentMemory
                                                                .mood.color,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        if (currentDist != null)
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .near_me_outlined,
                                                                size: 11,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onSurface
                                                                    .withValues(
                                                                        alpha:
                                                                            0.4),
                                                              ),
                                                              const SizedBox(
                                                                  width: 3),
                                                              Text(
                                                                _formatDistance(
                                                                    currentDist),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withValues(
                                                                          alpha:
                                                                              0.4),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      currentMemory.description,
                                                      style:
                                                          AppTextStyles.headline(
                                                              context),
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    if (currentMemory
                                                            .aiCaption !=
                                                        null) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        currentMemory
                                                            .aiCaption!,
                                                        style: AppTextStyles
                                                            .bodySecondary(
                                                                context)
                                                            .copyWith(
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
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

// ─── Annotation click listener ────────────────────────────────────────────────

// ignore: deprecated_member_use
class _AnnotationClickListener extends OnPointAnnotationClickListener {
  _AnnotationClickListener({
    required this.annotationMap,
    required this.onTap,
  });

  final Map<String, MemoryModel> annotationMap;
  final void Function(MemoryModel) onTap;

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    final memory = annotationMap[annotation.id];
    if (memory != null) onTap(memory);
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
