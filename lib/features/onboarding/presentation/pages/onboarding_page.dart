import 'dart:io';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ─── Mood colours (mirrors MemoryMoodX.color) ─────────────────────────────────

const _moodColors = [
  Color(0xFF7EB8D4), // echo   — sky blue
  Color(0xFFE8879C), // love   — rose
  Color(0xFF9B8ADE), // secret — purple
  Color(0xFFD4A847), // dream  — golden
  Color(0xFF5BC4B0), // lost   — teal
  Color(0xFFE8943B), // food   — orange
];

// ─── Dot layout config ────────────────────────────────────────────────────────

class _DotCfg {
  final Alignment alignment;
  final double size;
  final int colorIdx;
  final int delayMs;

  const _DotCfg({
    required this.alignment,
    required this.size,
    required this.colorIdx,
    required this.delayMs,
  });
}

const _dotConfigs = [
  _DotCfg(alignment: Alignment(-0.72, -0.74), size: 9,  colorIdx: 0, delayMs: 180),
  _DotCfg(alignment: Alignment( 0.62, -0.80), size: 7,  colorIdx: 1, delayMs: 320),
  _DotCfg(alignment: Alignment(-0.90, -0.28), size: 6,  colorIdx: 2, delayMs: 490),
  _DotCfg(alignment: Alignment( 0.85, -0.12), size: 10, colorIdx: 3, delayMs: 130),
  _DotCfg(alignment: Alignment(-0.55,  0.52), size: 7,  colorIdx: 4, delayMs: 580),
  _DotCfg(alignment: Alignment( 0.74,  0.62), size: 8,  colorIdx: 5, delayMs: 390),
  _DotCfg(alignment: Alignment( 0.18, -0.58), size: 5,  colorIdx: 2, delayMs: 670),
  _DotCfg(alignment: Alignment(-0.30,  0.80), size: 5,  colorIdx: 0, delayMs: 440),
  _DotCfg(alignment: Alignment( 0.92,  0.38), size: 4,  colorIdx: 1, delayMs: 240),
  _DotCfg(alignment: Alignment(-0.14, -0.88), size: 4,  colorIdx: 5, delayMs: 560),
];

// ─── Slide data ────────────────────────────────────────────────────────────────

class _Slide {
  final IconData icon;
  final String title;
  final String body;

  const _Slide({required this.icon, required this.title, required this.body});
}

const _slides = [
  _Slide(
    icon: LucideIcons.globe,
    title: 'Benvenuto in Echo.',
    body: 'Il mondo è pieno di storie.\nEcho ti aiuta a trovarle e a lasciarne di nuove.',
  ),
  _Slide(
    icon: LucideIcons.map,
    title: 'Esplora la mappa.',
    body: 'Ogni luogo custodisce un ricordo.\nNaviga la mappa e scopri cosa è accaduto intorno a te.',
  ),
  _Slide(
    icon: LucideIcons.plus,
    title: 'Lascia il tuo segno.',
    body: 'Crea ricordi geolocalizzati — foto, testo, emozioni — legati per sempre a un posto.',
  ),
  _Slide(
    icon: LucideIcons.users,
    title: 'Connettiti.',
    body: 'Segui le persone, commenta i loro ricordi e costruisci una rete di storie condivise.',
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

  late final AnimationController _exitCtrl;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _exitOpacity,
      child: AnimatedGradientBackground(
        child: Stack(
          children: [
            // ── Ambient blobs ─────────────────────────────────────────
            Align(
              alignment: Alignment.topRight,
              child: _GlowBlob(
                size: 280,
                color: AppColors.accent,
                opacity: isDark ? 0.14 : 0.10,
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: _GlowBlob(
                size: 220,
                color: AppColors.primary,
                opacity: isDark ? 0.06 : 0.08,
              ),
            ),

            // ── Mood dots layer ───────────────────────────────────────
            _MoodDotsLayer(isDark: isDark),

            // ── Main content ──────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_page + 1} / ${_slides.length}',
                          style: AppTextStyles.bodySecondary(context)
                              .copyWith(fontSize: 12),
                        ).animate().fadeIn(duration: 300.ms),

                        if (_page < _slides.length - 1)
                          GestureDetector(
                            onTap: _dismiss,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Text(
                                'Salta',
                                style: AppTextStyles.bodySecondary(context)
                                    .copyWith(fontSize: 14),
                              ),
                            ),
                          ).animate().fadeIn(duration: 300.ms),
                      ],
                    ),
                  ),

                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: _slides.length,
                      itemBuilder: (context, i) => _SlideContent(
                        slide: _slides[i],
                        isDark: isDark,
                        isFirst: i == 0,
                      ),
                    ),
                  ),

                  _BottomControls(
                    page: _page,
                    total: _slides.length,
                    isDark: isDark,
                    onNext: _next,
                  ),

                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mood dots layer ──────────────────────────────────────────────────────────

class _MoodDotsLayer extends StatelessWidget {
  final bool isDark;

  const _MoodDotsLayer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final cfg in _dotConfigs)
            Align(
              alignment: cfg.alignment,
              child: _MoodDot(cfg: cfg, isDark: isDark),
            ),
        ],
      ),
    );
  }
}

class _MoodDot extends StatelessWidget {
  final _DotCfg cfg;
  final bool isDark;

  const _MoodDot({required this.cfg, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = _moodColors[cfg.colorIdx];
    final baseOpacity = isDark ? 0.55 : 0.40;

    return Container(
      width: cfg.size,
      height: cfg.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: baseOpacity),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: baseOpacity * 0.7),
            blurRadius: cfg.size * 2.4,
            spreadRadius: 0,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: cfg.delayMs),
          duration: 800.ms,
          curve: Curves.easeOut,
        )
        .scale(
          begin: const Offset(0.2, 0.2),
          end: const Offset(1.0, 1.0),
          delay: Duration(milliseconds: cfg.delayMs),
          duration: 700.ms,
          curve: Curves.easeOutCubic,
        )
        // subtle continuous breathe after appearing
        .then(delay: Duration(milliseconds: cfg.delayMs + 400))
        .animate(
          onPlay: (c) => c.repeat(reverse: true),
        )
        .scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(1.18, 1.18),
          duration: Duration(milliseconds: 2800 + cfg.delayMs % 700),
          curve: Curves.easeInOut,
        );
  }
}

// ─── Slide content ─────────────────────────────────────────────────────────────

class _SlideContent extends StatelessWidget {
  final _Slide slide;
  final bool isDark;
  final bool isFirst;

  const _SlideContent({
    required this.slide,
    required this.isDark,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    // First slide: slow, dreamy dissolve. Others: snappier slide-in.
    final iconDuration  = isFirst ? 1000.ms : 520.ms;
    final iconCurve     = isFirst ? Curves.easeOut : Curves.easeOutBack;
    final iconScale     = isFirst ? const Offset(0.92, 0.92) : const Offset(0.82, 0.82);
    final textDelay1    = isFirst ? 300.ms  : 80.ms;
    final textDelay2    = isFirst ? 520.ms  : 160.ms;
    final textDuration  = isFirst ? 700.ms  : 420.ms;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          _SlideIllustration(icon: slide.icon, isDark: isDark)
              .animate()
              .fadeIn(duration: iconDuration, curve: Curves.easeOut)
              .scale(
                begin: iconScale,
                duration: iconDuration,
                curve: iconCurve,
              ),

          const SizedBox(height: 48),

          Text(
            slide.title,
            style: AppTextStyles.displayLarge(context).copyWith(fontSize: 34),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(delay: textDelay1, duration: textDuration)
              .slideY(
                begin: isFirst ? 0.06 : 0.12,
                end: 0,
                delay: textDelay1,
                duration: textDuration,
                curve: Curves.easeOut,
              ),

          const SizedBox(height: 16),

          Text(
            slide.body,
            style: AppTextStyles.bodySecondary(context)
                .copyWith(fontSize: 15, height: 1.6),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(delay: textDelay2, duration: textDuration)
              .slideY(
                begin: isFirst ? 0.05 : 0.10,
                end: 0,
                delay: textDelay2,
                duration: textDuration,
                curve: Curves.easeOut,
              ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

// ─── Illustration ─────────────────────────────────────────────────────────────

class _SlideIllustration extends StatelessWidget {
  final IconData icon;
  final bool isDark;

  const _SlideIllustration({required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accentBorder = AppColors.accent.withValues(alpha: isDark ? 0.18 : 0.14);
    final accentFill   = AppColors.accent.withValues(alpha: isDark ? 0.06 : 0.05);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentFill,
            border: Border.all(color: accentBorder, width: 1),
          ),
        ),
        Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: isDark ? 0.08 : 0.07),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: isDark ? 0.22 : 0.18),
              width: 1,
            ),
          ),
        ),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: isDark ? 0.16 : 0.12),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: isDark ? 0.32 : 0.24),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: isDark ? 0.35 : 0.20),
                blurRadius: 48,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 42, color: AppColors.accent),
        ),
      ],
    );
  }
}

// ─── Bottom controls ──────────────────────────────────────────────────────────

class _BottomControls extends StatelessWidget {
  final int page;
  final int total;
  final bool isDark;
  final VoidCallback onNext;

  const _BottomControls({
    required this.page,
    required this.total,
    required this.isDark,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = page == total - 1;
    final isIOS  = Platform.isIOS || Platform.isMacOS;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (i) {
              final active = i == page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width:  active ? 24 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent
                      : AppColors.accent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),

          const SizedBox(height: 28),

          isLast
              ? SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Inizia a esplorare',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                )
              : _GlassButton(isDark: isDark, isIOS: isIOS, onTap: onNext),
        ],
      ),
    );
  }
}

// ─── Glass "Avanti" button ────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final bool isDark;
  final bool isIOS;
  final VoidCallback onTap;

  const _GlassButton({
    required this.isDark,
    required this.isIOS,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blurSigma = isIOS ? 28.0 : 18.0;
    final bg = isDark
        ? Colors.white.withValues(alpha: isIOS ? 0.10 : 0.08)
        : Colors.white.withValues(alpha: isIOS ? 0.65 : 0.55);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.80);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border, width: isIOS ? 0.5 : 1.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Avanti',
                  style: AppTextStyles.body(context).copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.arrowRight,
                  size: 17,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _GlowBlob({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity * 2.5),
            blurRadius: 60,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}
