import 'package:echo/core/theme/app_radius.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/services/permission_gate.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/domain/drop_relation.dart';
import 'package:echo/features/drop/presentation/widgets/relation_badge.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'package:echo/shared/widgets/navigation/floating_navbar.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/map/presentation/widgets/map_tutorial_overlay.dart';
import 'package:echo/features/map/providers/map_tutorial_provider.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/core/services/drop_image_signer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum _MapFilter { all, circle, mine }

class _MapPageState extends ConsumerState<MapPage> {
  MapLibreMapController? _mapController;

  // symbol → cluster (single or multi drop)
  final Map<Symbol, _DropCluster> _symbolMap = {};

  final Map<DropRelation, Uint8List> _relationImages = {};

  // count → pre-rendered cluster badge PNG bytes
  final Map<int, Uint8List> _clusterImages = {};

  final Map<String, Uint8List> _photoPinImages = {};
  final Map<String, ui.Image> _photoCache = {};
  // Ultimo punto in cui abbiamo chiesto i drop: spostamenti piccoli della
  // mappa non rifanno la richiesta (i drop arrivano già da un raggio di 5 km).
  LatLng? _lastNearbyCenter;
  DateTime? _lastNearbyAt;
  int _nearbySeq = 0;

  // dropIds currently being fetched/rendered, to avoid duplicate work
  final Set<String> _photoFetchInFlight = {};

  _MapFilter _filter = _MapFilter.all;
  static const _allVisibilities = {'public', 'circle', 'private'};

  bool _showMarkers = false;
  bool _showCrosshair = false;
  bool _dropDiscovered = false;
  bool _mapReady = false;
  bool _viewportLoadEnabled = false;
  geo.Position? _userPosition;
  List<DropModel> _rawDrops = [];
  bool _loading = true;
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

  final _pageCtrl = PageController(viewportFraction: 0.86);
  int _page = 0;
  bool _programmaticPage = false;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  List<DropModel> get _drops {
    if (_filter == _MapFilter.all) return _rawDrops;
    final want = _filter == _MapFilter.circle
        ? DropRelation.circle
        : DropRelation.mine;
    return _rawDrops.where((d) => _relationFor(d) == want).toList();
  }

  void _setDrops(List<DropModel> drops) {
    final keepId = _currentDrop?.id;
    _rawDrops = drops;
    _loading = false;
    final sorted = _sortedByDistance;
    final idx = keepId == null ? -1 : sorted.indexWhere((d) => d.id == keepId);
    _page = idx >= 0
        ? idx
        : (sorted.isEmpty ? 0 : _page.clamp(0, sorted.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients && _pageCtrl.page?.round() != _page) {
        _programmaticPage = true;
        _pageCtrl.jumpToPage(_page);
        _programmaticPage = false;
      }
    });
  }

  Future<void> _focusDrop(DropModel drop) async {
    final idx = _sortedByDistance.indexWhere((d) => d.id == drop.id);
    if (idx >= 0) {
      setState(() => _page = idx);
      if (_pageCtrl.hasClients) {
        _programmaticPage = true;
        await _pageCtrl.animateToPage(
          idx,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
        _programmaticPage = false;
      }
    }
    await _flyToDrop(drop);
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    if (_programmaticPage) return;
    HapticFeedback.selectionClick();
    final sorted = _sortedByDistance;
    if (i < sorted.length) _flyToDrop(sorted[i]);
  }

  Future<void> _onFilterChanged(_MapFilter f) async {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _page = 0;
    });
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    await _syncAnnotations();
    final first = _currentDrop;
    if (first != null) await _flyToDrop(first);
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
      ..arcTo(
        Rect.fromCircle(center: center, radius: r),
        rightAngle,
        sweep,
        false,
      )
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
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  // ─── Single-drop pin rendering ─────────────────────────────────────────────

  Future<void> _preRenderRelationImages() async {
    for (final rel in DropRelation.values) {
      _relationImages[rel] = await _renderSinglePin(rel);
    }
  }

  DropRelation _relationFor(DropModel drop) => relationOf(
    drop,
    myId: ref.read(currentUserProvider)?.id,
    circleIds: ref.read(circleIdsProvider),
  );

  String _pinKey(DropModel drop) {
    final rel = _relationFor(drop);
    final photoKey = 'pin-photo-${rel.name}-${drop.id}';
    return _photoPinImages.containsKey(photoKey) ? photoKey : 'rel-${rel.name}';
  }

  Future<void> _recolorPins() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    for (final entry in _symbolMap.entries.toList()) {
      if (!entry.value.isSingle) continue;
      final drop = entry.value.first;
      try {
        await ctrl.updateSymbol(
          entry.key,
          SymbolOptions(iconImage: _pinKey(drop)),
        );
      } catch (_) {}
      _ensurePhotoPin(drop);
    }
  }

  /// Renders a downward-pointing pin. When [photo] is supplied it fills the
  /// inner preview circle (cover-fit); otherwise the mood's outline icon is
  /// used as a fallback while the photo loads (or when there isn't one).
  Future<Uint8List> _renderSinglePin(
    DropRelation rel, {
    ui.Image? photo,
  }) async {
    const double r = 70.0;
    const double tipDistance = 98.0;
    const double sidePad = 20.0;
    const double topPad = 20.0;
    const double width = r * 2 + sidePad * 2;
    const double height = topPad + r + tipDistance + 3.0;
    final color = rel.color;
    final bodyColor = color;
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
            Color.lerp(bodyColor, Colors.black, 0.2)!,
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
      Paint()..color = AppColors.darkBackground,
    );
    if (photo != null) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: innerR)),
      );
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: center, radius: innerR),
        image: photo,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(
        center,
        innerR,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      _drawIconGlyph(
        canvas,
        Icons.photo_camera_rounded,
        center,
        innerR * 0.9,
        color,
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<ui.Image> _loadNetworkImage(String url) {
    final completer = Completer<ui.Image>();
    // Il pallino è un cerchio di 140 px: decodifichiamo la foto già
    // rimpicciolita, altrimenti ogni pin terrebbe in memoria la foto intera
    // (~7 MB) e con tanti drop sulla mappa il telefono chiuderebbe l'app.
    final stream = ResizeImage(
      CachedNetworkImageProvider(url, cacheKey: DropImageSigner.cacheKey(url)),
      width: 280,
      height: 280,
      policy: ResizeImagePolicy.fit,
    ).resolve(const ImageConfiguration());
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
    final url = drop.imageUrl;
    if (url == null) return;
    final rel = _relationFor(drop);
    final key = 'pin-photo-${rel.name}-${drop.id}';
    if (_photoPinImages.containsKey(key) || _photoFetchInFlight.contains(key)) {
      return;
    }

    _photoFetchInFlight.add(key);
    final cached = _photoCache[drop.id];
    (cached != null ? Future.value(cached) : _loadNetworkImage(url))
        .then((image) async {
          _photoCache[drop.id] = image;
          final bytes = await _renderSinglePin(rel, photo: image);
          if (!mounted) return;
          _photoPinImages[key] = bytes;
          final ctrl = _mapController;
          if (ctrl == null) return;
          try {
            await ctrl.addImage(key, bytes);
          } catch (_) {
            return;
          }
          for (final entry in _symbolMap.entries) {
            if (entry.value.isSingle && entry.value.first.id == drop.id) {
              if (_pinKey(drop) != key) break;
              try {
                await ctrl.updateSymbol(
                  entry.key,
                  SymbolOptions(iconImage: key),
                );
              } catch (_) {}
              break;
            }
          }
        })
        .catchError((_) {})
        .whenComplete(() => _photoFetchInFlight.remove(key));
  }

  // ─── Cluster pin rendering ─────────────────────────────────────────────────

  Future<Uint8List> _renderClusterPin(int count) async {
    // Dot-pin del brand (vedi paintDotPin): spazio 240×240, corpo x 64→176,
    // punta a y 190, badge centrato in (168, 64). Ritagliamo l'area utile
    // tenendo la punta al centro in basso (iconAnchor: 'bottom').
    const double scale = 1.2;
    const double left = 52, top = 40;
    const double width = (120 - left) * 2 * scale;
    const double height = (190 - top) * scale + 4;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.scale(scale);
    canvas.translate(-left, -top);
    // Neutro: il colore sulla mappa ha un senso (rosa cerchia, ambra
    // pubblici, bianco i tuoi) e un gruppo può contenere drop di ogni tipo.
    paintDotPin(
      canvas,
      color: AppColors.darkSurfaceHigh,
      count: count,
      faceColor: AppColors.paper,
      badgeColor: AppColors.paper,
      badgeTextColor: AppColors.ink,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ─── Style loaded — called at init and on every style change ─────────────

  Future<void> _onStyleLoaded() async {
    // Symbols are wiped when the style reloads; clear stale references
    _symbolMap.clear();

    if (_relationImages.isEmpty) {
      await _preRenderRelationImages();
    }
    for (final entry in _relationImages.entries) {
      try {
        await _mapController!.addImage('rel-${entry.key.name}', entry.value);
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
        await _mapController!.addImage(entry.key, entry.value);
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
          if (_relationImages.isEmpty) continue;
          imageKey = _pinKey(drop);
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
      _focusDrop(cluster.first);
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
          _focusDrop(m);
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
      setState(() => _setDrops([]));
      EchoToast.show(
        context,
        'Posizione non disponibile. Attiva il GPS per vedere e lasciare drop vicino a te.',
        type: EchoToastType.error,
      );
      return;
    }

    _lastNearbyCenter = LatLng(pos.latitude, pos.longitude);
    _lastNearbyAt = DateTime.now();
    final seq = ++_nearbySeq;
    final nearby = await ref
        .read(dropRepositoryProvider)
        .getNearbyDrops(
          lat: pos.latitude,
          lng: pos.longitude,
          visibilities: _allVisibilities,
        );

    if (!mounted || seq != _nearbySeq) return;
    setState(() => _setDrops(nearby));

    if (_mapReady) await _flyToUserAndReveal();
  }

  Future<void> _refreshNearby({bool force = false}) async {
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
    final last = _lastNearbyCenter;
    final lastAt = _lastNearbyAt;
    if (!force &&
        last != null &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < const Duration(seconds: 45) &&
        geo.Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              lat,
              lng,
            ) <
            400) {
      return;
    }
    _lastNearbyCenter = LatLng(lat, lng);
    _lastNearbyAt = DateTime.now();
    final seq = ++_nearbySeq;
    final nearby = await ref
        .read(dropRepositoryProvider)
        .getNearbyDrops(lat: lat, lng: lng, visibilities: _allVisibilities);
    // Se nel frattempo la mappa si è spostata ed è partita un'altra
    // richiesta, questa risposta è vecchia: la ignoriamo.
    if (!mounted || seq != _nearbySeq) return;
    setState(() => _setDrops(nearby));
    await _syncAnnotations();
  }

  Future<geo.Position?> _initLocation() async {
    try {
      final perm = await PermissionGate.run(
        () => geo.Geolocator.requestPermission(),
      );
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
    final drops = _drops;
    if (_userPosition == null) return drops;
    final list = List<DropModel>.from(drops);
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
    final sorted = _sortedByDistance;
    if (sorted.isEmpty) return null;
    return sorted[_page.clamp(0, sorted.length - 1)];
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

    if (!_rawDrops.any((m) => m.id == drop.id)) {
      setState(() => _setDrops([..._rawDrops, drop]));
      needsSync = true;
    }
    if (!_drops.any((m) => m.id == drop.id)) {
      setState(() => _filter = _MapFilter.all);
      needsSync = true;
    }

    if (!_showMarkers) {
      setState(() {
        _showMarkers = true;
        _showCrosshair = true;
      });
    }

    if (needsSync) await _syncAnnotations();
    if (!mounted) return;

    setState(() => _dropDiscovered = true);
    await _focusDrop(drop);
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

  Widget _carousel() {
    final sorted = _sortedByDistance;
    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: _EmptyCard(filter: _filter, onCreate: _createFromMap),
      );
    }
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: sorted.length,
      onPageChanged: _onPageChanged,
      padEnds: false,
      itemBuilder: (context, i) {
        final drop = sorted[i];
        final active = i == _page;
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 18 : 6, right: 6),
          child: AnimatedScale(
            scale: active ? 1 : 0.94,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _DropCarouselCard(
              drop: drop,
              active: active,
              distance: _distanceTo(drop),
              formatDistance: _formatDistance,
              onTap: () {
                if (!active) {
                  _focusDrop(drop);
                } else {
                  openDropDetail(context, drop);
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(circleIdsProvider, (_, _) async {
      await _recolorPins();
      if (_filter != _MapFilter.all && mounted) {
        setState(() {});
        await _syncAnnotations();
      }
    });
    ref.listen(discoverProvider, (_, _) {
      if (_mapReady) _refreshNearby(force: true);
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
                          AppColors.darkBackground,
                          AppColors.darkSurface,
                          AppColors.darkBackground,
                        ]
                      : const [
                          AppColors.lightBackground,
                          AppColors.lightSurfaceSoft,
                          AppColors.lightBackground,
                        ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: const MingleWordmark(
                  fontSize: 18,
                  color: AppColors.accent,
                  dotColor: AppColors.accentSecondary,
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

          IgnorePointer(
            child: Container(
              height: MediaQuery.paddingOf(context).top + 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.darkBackground.withValues(alpha: 0.85),
                    AppColors.darkBackground.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const MingleWordmark(
                        fontSize: 26,
                        color: AppColors.accent,
                        dotColor: AppColors.accentSecondary,
                      ),
                      const Spacer(),
                      _CountPill(count: _drops.length, loading: _loading),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _filterRowKey,
                    child: _RelationFilter(
                      value: _filter,
                      onChanged: _onFilterChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: FloatingNavbar.reservedHeight + 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Column(
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
                          primary: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 700),
                  offset: _dropDiscovered || (!_loading && _drops.isEmpty)
                      ? Offset.zero
                      : const Offset(0, 0.4),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: _dropDiscovered || (!_loading && _drops.isEmpty)
                        ? 1
                        : 0,
                    child: SizedBox(
                      key: _cardAreaKey,
                      height: 116,
                      child: _carousel(),
                    ),
                  ),
                ),
              ],
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

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.loading});
  final int count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? 'Cerco drop…'
        : count == 0
        ? 'Nessun drop qui'
        : '$count drop qui intorno';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.darkBackground.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiveDot(active: !loading && count > 0),
          const SizedBox(width: 7),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              text,
              key: ValueKey(text),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.active});
  final bool active;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? AppColors.success
        : Colors.white.withValues(alpha: 0.4);
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 6 + 8 * _c.value,
                height: 6 + 8 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.4 * (1 - _c.value)),
                ),
              ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationFilter extends StatelessWidget {
  const _RelationFilter({required this.value, required this.onChanged});
  final _MapFilter value;
  final ValueChanged<_MapFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterPill(
          label: 'Tutti',
          dots: const [
            AppColors.accentSecondary,
            AppColors.accent,
            Colors.white,
          ],
          selected: value == _MapFilter.all,
          onTap: () => onChanged(_MapFilter.all),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          label: 'Cerchia',
          dots: [DropRelation.circle.color],
          selected: value == _MapFilter.circle,
          onTap: () => onChanged(_MapFilter.circle),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          label: 'Miei',
          dots: [DropRelation.mine.color],
          selected: value == _MapFilter.mine,
          onTap: () => onChanged(_MapFilter.mine),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.dots,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<Color> dots;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: selected
              ? Colors.white
              : AppColors.darkBackground.withValues(alpha: 0.82),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8.0 + (dots.length - 1) * 5,
              height: 8,
              child: Stack(
                children: [
                  for (var i = 0; i < dots.length; i++)
                    Positioned(
                      left: i * 5.0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dots[i],
                          border: Border.all(
                            color: selected
                                ? AppColors.darkSurfaceHigh
                                : AppColors.darkBackground,
                            width: dots[i] == Colors.white && selected
                                ? 1
                                : 0.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.darkBackground
                    : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropCarouselCard extends StatelessWidget {
  const _DropCarouselCard({
    required this.drop,
    required this.active,
    required this.distance,
    required this.formatDistance,
    required this.onTap,
  });

  final DropModel drop;
  final bool active;
  final double? distance;
  final String Function(double) formatDistance;
  final VoidCallback onTap;

  String _ago() {
    final d = DateTime.now().difference(drop.createdAt);
    if (d.inMinutes < 1) return 'ora';
    if (d.inMinutes < 60) return '${d.inMinutes} min fa';
    if (d.inHours < 24) return '${d.inHours} h fa';
    if (d.inDays < 7) return '${d.inDays} g fa';
    final local = drop.createdAt.toLocal();
    return '${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final author = drop.author;
    final name = author == null
        ? null
        : (author.displayName.isNotEmpty
              ? author.displayName
              : author.username);
    final meta = [
      ?name,
      if (distance != null) formatDistance(distance!),
      _ago(),
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.darkSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.16 : 0.07),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 94,
                height: 94,
                child: drop.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: drop.imageUrl!,
                        cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (_, _) => const DropPlaceholder(),
                        errorWidget: (_, _, _) => const DropPlaceholder(),
                      )
                    : const DropPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RelationBadge(drop: drop),
                  const SizedBox(height: 7),
                  Text(
                    drop.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: active ? 0.6 : 0.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.filter, required this.onCreate});
  final _MapFilter filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (filter) {
      _MapFilter.all => (
        'Ancora niente qui',
        'Sii il primo a lasciare un drop in questa zona.',
      ),
      _MapFilter.circle => (
        'La tua cerchia tace',
        'Nessun drop dei tuoi amici in questa zona.',
      ),
      _MapFilter.mine => (
        'Nessun tuo drop qui',
        'Lasciane uno dove ti trovi adesso.',
      ),
    };
    return GestureDetector(
      onTap: onCreate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.darkSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.add_location_alt_rounded,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                    ),
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

// ─── Map circle button (locate / add) ────────────────────────────────────────

class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback onTap;

  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: primary ? 56 : 48,
        height: primary ? 56 : 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary
              ? AppColors.accent
              : AppColors.darkBackground.withValues(alpha: 0.82),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Icon(icon, color: Colors.white, size: primary ? 26 : 22),
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
    final bg = isDark ? AppColors.darkSurface : Colors.white;

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
              color: AppColors.textSecondaryLight.withValues(alpha: 0.35),
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
                      ? AppColors.success
                      : AppColors.textSecondaryLight.withValues(alpha: 0.35),
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
                cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
                fit: BoxFit.cover,
                memCacheWidth: 600,
                placeholder: (_, _) => const DropPlaceholder(),
                errorWidget: (_, _, _) => const DropPlaceholder(),
              )
            else
              const DropPlaceholder(),

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
                  RelationBadge(drop: drop, overlay: true),
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
