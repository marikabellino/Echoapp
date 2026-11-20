import 'package:echo/core/services/permission_gate.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_motion.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/home_zone/home_zone.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Apre la pagina "La tua zona casa".
/// [firstRun]: mostrata in automatico al primo accesso: sale dal basso, non
/// si chiude col gesto indietro e offre "Più tardi".
Future<void> openHomeZonePage(BuildContext context, {bool firstRun = false}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: firstRun,
      builder: (_) => HomeZonePage(firstRun: firstRun),
    ),
  );
}

class HomeZonePage extends ConsumerStatefulWidget {
  const HomeZonePage({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  ConsumerState<HomeZonePage> createState() => _HomeZonePageState();
}

class _HomeZonePageState extends ConsumerState<HomeZonePage> {
  // Posizione scelta in questo pannello (non ancora salvata).
  double? _lat, _lng;
  String? _label;
  double? _accuracy;
  double _radius = HomeZone.defaultRadius;

  bool _locating = false;
  bool _searching = false;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  List<({double lat, double lng, String label})> _results = const [];

  @override
  void initState() {
    super.initState();
    final zone = ref.read(homeZoneProvider).asData?.value.zone;
    if (zone != null) {
      _lat = zone.lat;
      _lng = zone.lng;
      _label = zone.label;
      _radius = zone.radiusMeters;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String m, {EchoToastType type = EchoToastType.info}) {
    if (mounted) EchoToast.show(context, m, type: type);
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) {
        _toast(
          'Attiva la posizione del telefono, oppure cerca il tuo indirizzo.',
          type: EchoToastType.error,
        );
        return;
      }
      final perm = await PermissionGate.run(
        () => geo.Geolocator.requestPermission(),
      );
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        _toast(
          'Senza il permesso di posizione puoi cercare il tuo indirizzo.',
          type: EchoToastType.error,
        );
        return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _accuracy = pos.accuracy;
        _label = null;
        _searchOpen = false;
        // Se il GPS è impreciso, allarghiamo il raggio per stare sicuri.
        if (pos.accuracy > 60 && _radius < 400) _radius = 400;
      });
    } catch (_) {
      _toast(
        'Non riesco a trovare la posizione. Riprova o cerca il tuo indirizzo.',
        type: EchoToastType.error,
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 4) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final locs = await gc.locationFromAddress(q);
      final out = <({double lat, double lng, String label})>[];
      for (final l in locs.take(3)) {
        String label = q;
        try {
          final m = (await gc.placemarkFromCoordinates(
            l.latitude,
            l.longitude,
          )).first;
          label = [
            [
              m.street,
              m.subThoroughfare,
            ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' '),
            m.locality,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
          if (label.isEmpty) label = q;
        } catch (_) {}
        out.add((lat: l.latitude, lng: l.longitude, label: label));
      }
      if (!mounted) return;
      setState(() => _results = out);
      if (out.isEmpty) {
        _toast('Nessun risultato. Prova con via, numero e città.');
      }
    } catch (_) {
      setState(() => _results = const []);
      _toast('Nessun risultato. Prova con via, numero e città.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null) return;
    await ref
        .read(homeZoneProvider.notifier)
        .save(
          HomeZone(
            lat: _lat!,
            lng: _lng!,
            radiusMeters: _radius,
            label: _label,
          ),
        );
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop();
    _toastAfterPop('Zona casa salvata. I drop da casa ora sono protetti.');
  }

  Future<void> _remove() async {
    await ref.read(homeZoneProvider.notifier).clear();
    if (!mounted) return;
    Navigator.of(context).pop();
    _toastAfterPop('Zona casa rimossa da questo telefono.');
  }

  Future<void> _later() async {
    await ref.read(homeZoneProvider.notifier).markPrompted();
    if (mounted) Navigator.of(context).pop();
  }

  void _toastAfterPop(String msg) {
    final ctx = Navigator.of(context, rootNavigator: true).context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctx.mounted) {
        EchoToast.show(ctx, msg, type: EchoToastType.success);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(homeZoneProvider).asData?.value.zone;
    final picked = _lat != null && _lng != null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Al primo accesso si esce solo con "Più tardi" o salvando.
    final canLeave = !widget.firstRun || existing != null;

    final content = SafeArea(
      bottom: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingGlassHeaderDelegate(
              isDark: isDark,
              minExtent: 52,
              maxExtent: 72,
              padding: const EdgeInsets.fromLTRB(12, 16, 20, 8),
              pinnedGap: 0,
              pinned: (context) => Row(
                children: [
                  if (canLeave) ...[
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                  ] else
                    const SizedBox(width: 8),
                  Text(
                    'Zona casa',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              dissolving: (context) => const SizedBox.shrink(),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              22,
              8,
              22,
              MediaQuery.paddingOf(context).bottom + bottom + 24,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: HomeDot(size: 150)),
                  const SizedBox(height: 10),
                  Text(
                    'La tua zona casa',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayLarge(
                      context,
                    ).copyWith(fontSize: 30),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Usa mingle anche da casa: i drop lasciati qui '
                    'non avranno un punto sulla mappa, non saranno mai pubblici '
                    'e nel feed comparirà solo «A casa».',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(context).copyWith(
                      color: AppColors.textSecondaryLight,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Reassure(),
                  const SizedBox(height: 20),

                  AnimatedSwitcher(
                    duration: AppMotion.pop,
                    child: picked ? _pickedView(context) : _chooseView(context),
                  ),

                  const SizedBox(height: 10),
                  if (widget.firstRun && existing == null)
                    TextButton(
                      onPressed: _later,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondaryLight,
                      ),
                      child: const Text(
                        'Più tardi (la trovi nelle Impostazioni)',
                      ),
                    )
                  else if (existing != null)
                    TextButton(
                      onPressed: _remove,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Rimuovi zona casa'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: canLeave,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: isDark
            ? AnimatedGradientBackground(child: content)
            : ColoredBox(color: AppColors.lightBackground, child: content),
      ),
    );
  }

  Widget _chooseView(BuildContext context) {
    return Column(
      key: const ValueKey('choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: GradientButton(
            onPressed: _locating ? null : _useGps,
            child: _locating
                ? const MingleDotsLoader(size: 20, color: Colors.white)
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Sono a casa adesso'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        if (!_searchOpen)
          OutlinedButton.icon(
            onPressed: () => setState(() => _searchOpen = true),
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text('Cerca il mio indirizzo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.paper,
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: AppColors.paper.withValues(alpha: .2)),
            ),
          )
        else ...[
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Via, numero civico, città',
              prefixIcon: const Icon(Icons.home_outlined),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: MingleDotsLoader(
                        size: 14,
                        color: AppColors.accent,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _search,
                    ),
            ),
          ),
          for (final r in _results)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.place_outlined),
              title: Text(r.label),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _lat = r.lat;
                  _lng = r.lng;
                  _label = r.label;
                  _accuracy = null;
                  _results = const [];
                  _searchOpen = false;
                });
              },
            ),
        ],
      ],
    );
  }

  Widget _pickedView(BuildContext context) {
    final where =
        _label ??
        (_accuracy != null
            ? 'La tua posizione attuale (± ${_accuracy!.round()} m)'
            : 'La posizione che hai scelto');
    return Column(
      key: const ValueKey('picked'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceLight,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.home_rounded, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  where,
                  style: AppTextStyles.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _lat = null;
                  _lng = null;
                }),
                child: const Text('Cambia'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Quanto è grande la zona?',
          style: AppTextStyles.body(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Più è grande, più sei protetto anche se il GPS sbaglia di qualche '
          'metro o abiti in un palazzo grande.',
          style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final r in HomeZone.radii) ...[
              Expanded(
                child: _RadiusChip(
                  meters: r,
                  selected: _radius == r,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _radius = r);
                  },
                ),
              ),
              if (r != HomeZone.radii.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: GradientButton(
            onPressed: _save,
            child: const Text('Salva zona casa'),
          ),
        ),
      ],
    );
  }
}

class _Reassure extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'La posizione di casa resta solo su questo telefono. '
              'Non la mandiamo a nessuno, nemmeno a noi.',
              style: AppTextStyles.bodySecondary(
                context,
              ).copyWith(color: AppColors.paper, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadiusChip extends StatelessWidget {
  const _RadiusChip({
    required this.meters,
    required this.selected,
    required this.onTap,
  });
  final double meters;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.pop,
        curve: AppMotion.popCurve,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.paper : AppColors.darkSurfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '${meters.round()} m',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.ink : AppColors.paper,
          ),
        ),
      ),
    );
  }
}

/// Dot al sicuro dentro la sua casetta, con il lucchetto sul tetto.
class HomeDot extends StatelessWidget {
  const HomeDot({super.key, this.size = 150});
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(size: Size(s, s), painter: _HousePainter()),
          Positioned(
            bottom: s * .1,
            child: MingleDot(size: s * .46, face: DotFace.love, wobble: .03),
          ),
          Positioned(
            top: s * .02,
            child: Container(
              width: s * .2,
              height: s * .2,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkSurface, width: 3),
              ),
              child: Icon(
                Icons.lock_rounded,
                size: s * .1,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .14, h * .42, w * .72, h * .54),
      Radius.circular(w * .08),
    );
    canvas.drawRRect(body, Paint()..color = AppColors.darkSurfaceHigh);
    final roof = Path()
      ..moveTo(w * .04, h * .48)
      ..lineTo(w * .5, h * .1)
      ..lineTo(w * .96, h * .48);
    canvas.drawPath(
      roof,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .07
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HousePainter old) => false;
}
