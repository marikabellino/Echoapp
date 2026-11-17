import 'dart:math' as math;

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_motion.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:echo/shared/widgets/gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Onboarding nello stile del brand kit: ogni slide è un "poster" con un palco
// scuro dove vive un'animazione, titolo grande a sinistra e un
// solo pulsante magenta in basso, sempre uguale.

class _Slide {
  final String title;
  final String body;
  final _Art art;

  const _Slide({required this.title, required this.body, required this.art});
}

enum _Art { hello, map, drop, party, circle }

const _slides = [
  _Slide(
    art: _Art.hello,
    title: 'Benvenuto in mingle.',
    body: 'La mappa segreta della tua città, scritta da te e dai tuoi amici.',
  ),
  _Slide(
    art: _Art.map,
    title: 'Esplora la mappa.',
    body:
        'Intorno a te ci sono drop lasciati da altri. Avvicinati per '
        'scoprirli: il colore ti dice di chi sono.',
  ),
  _Slide(
    art: _Art.drop,
    title: 'Lascia il tuo segno.',
    body: 'Una foto, due parole, un posto. Chi passerà di lì lo troverà.',
  ),
  _Slide(
    art: _Art.party,
    title: 'Serate, club, concerti.',
    body:
        'Ogni evento ha la sua mappa. Lascia drop durante la serata e '
        'rivivila dopo con chi c\'era.',
  ),
  _Slide(
    art: _Art.circle,
    title: 'La tua cerchia.',
    body:
        'Aggiungi i tuoi amici, taggali nei drop e scopri la città '
        'attraverso i loro occhi.',
  ),
];

// ─── Page ─────────────────────────────────────────────────────────────────────

class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingPage({super.key, required this.onDone});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  bool _exiting = false;

  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _pageCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (!_isLast) {
      await _pageCtrl.nextPage(
        duration: AppMotion.mingle,
        curve: AppMotion.mingleCurve,
      );
    } else {
      await _dismiss();
    }
  }

  Future<void> _dismiss() async {
    if (_exiting) return;
    setState(() => _exiting = true);
    await _exitCtrl.forward();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: ReverseAnimation(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInOut),
      ),
      child: ColoredBox(
        color: AppColors.ink,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Top bar ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 12, 0),
                child: Row(
                  children: [
                    const MingleWordmark(
                      fontSize: 24,
                      color: AppColors.paper,
                      dotColor: AppColors.accent,
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: AppMotion.pop,
                      child: TextButton(
                        onPressed: _isLast ? null : _dismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondaryLight,
                        ),
                        child: const Text('Salta'),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Progress a segmenti ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: _SegmentedProgress(
                  controller: _pageCtrl,
                  total: _slides.length,
                ),
              ),

              // ── Slides ──────────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _slides.length,
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _pageCtrl,
                    builder: (context, _) {
                      final page =
                          _pageCtrl.hasClients &&
                              _pageCtrl.position.haveDimensions
                          ? _pageCtrl.page ?? 0
                          : 0.0;
                      return _SlideView(
                        slide: _slides[i],
                        offset: (i - page).clamp(-1.0, 1.0),
                      );
                    },
                  ),
                ),
              ),

              // ── CTA ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: GradientButton(
                    onPressed: _next,
                    child: AnimatedSwitcher(
                      duration: AppMotion.pop,
                      switchInCurve: AppMotion.popCurve,
                      transitionBuilder: (child, a) => ScaleTransition(
                        scale: a,
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: Text(
                        _isLast ? 'Inizia a esplorare' : 'Avanti',
                        key: ValueKey(_isLast),
                      ),
                    ),
                  ),
                ),
              ),

              Transform.rotate(
                angle: -0.03,
                child: const MingleMarquee(fontSize: 20),
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Progress ────────────────────────────────────────────────────────────────

class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.controller, required this.total});

  final PageController controller;
  final int total;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? 0
            : 0.0;
        return Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(color: AppColors.darkSurfaceHigh),
                        FractionallySizedBox(
                          widthFactor: (page - i + 1).clamp(0.0, 1.0),
                          child: Container(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─── Slide ───────────────────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.offset});

  final _Slide slide;

  /// -1 … 1: quanto la slide è spostata rispetto al centro (parallasse).
  final double offset;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final fade = (1 - offset.abs() * 1.2).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Palco: l'illustrazione si muove più lentamente del testo.
          Expanded(
            child: _Stage(
              child: Transform.translate(
                offset: Offset(offset * w * 0.35, 0),
                child: Transform.scale(
                  scale: 1 - offset.abs() * 0.25,
                  child: _art(slide.art),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 150,
            child: Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(offset * 40, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slide.title,
                      style: AppTextStyles.displayLarge(
                        context,
                      ).copyWith(fontSize: 36, height: 1.0),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.body,
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _art(_Art art) => switch (art) {
    _Art.hello => const _HelloArt(),
    _Art.map => const _MapArt(),
    _Art.drop => const DropEcho(size: 210, loop: true),
    _Art.party => const PartyDot(size: 240),
    _Art.circle => const MingleLogomark(size: 130),
  };
}

/// Il "palco" del brand kit: pannello scuro con un alone magenta.
class _Stage extends StatelessWidget {
  const _Stage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            border: Border.all(color: AppColors.borderDark),
            borderRadius: BorderRadius.circular(36),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.22),
                      blurRadius: 90,
                    ),
                  ],
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Illustrazioni ───────────────────────────────────────────────────────────

/// Slide 1: Dot grande che ti segue con lo sguardo e saluta (occhiolino).
class _HelloArt extends StatefulWidget {
  const _HelloArt();

  @override
  State<_HelloArt> createState() => _HelloArtState();
}

class _HelloArtState extends State<_HelloArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value;
        // Guarda in giro, e verso la fine del ciclo fa l'occhiolino.
        final look = Offset(
          math.sin(t * math.pi * 2) * 0.8,
          math.cos(t * math.pi * 4) * 0.3,
        );
        final wink = t > 0.82 && t < 0.94;
        final hop = t > 0.8 && t < 0.9
            ? math.sin((t - .8) / .1 * math.pi)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -hop * 18),
          child: MingleDot(
            size: 170,
            face: wink ? DotFace.wink : DotFace.happy,
            look: look,
          ),
        );
      },
    );
  }
}

/// Slide 2: tre pin con i colori della mappa e la loro legenda.
class _MapArt extends StatelessWidget {
  const _MapArt();

  @override
  Widget build(BuildContext context) {
    Widget pin(Color c, String label, double size, int? count) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MinglePin(size: size, color: c, count: count),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySecondary(
            context,
          ).copyWith(fontWeight: FontWeight.w600, color: AppColors.paper),
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pin(AppColors.paper, 'Tuoi', 84, null),
        pin(AppColors.accent, 'Cerchia', 120, 3),
        pin(AppColors.accentSecondary, 'Pubblici', 84, null),
      ],
    );
  }
}
