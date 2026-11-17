import 'dart:math' as math;

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_motion.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Tour guidato della mappa al primo accesso, nello stile del brand:
// niente sfumature, una scia di puntini che "cammina" verso l'elemento da
// guardare e un piccolo Dot animato che spiega ogni passo.

enum _Art { look, colors, swipe, drop }

class _TutorialStep {
  const _TutorialStep({
    required this.art,
    required this.title,
    required this.body,
    required this.target,
    required this.bubble,
  });

  final _Art art;
  final String title;
  final String body;

  /// Dove sta l'elemento evidenziato (-1..1 per asse), se non misurato.
  final Alignment target;

  /// Dove sta la card di testo (-1..1 per asse).
  final Alignment bubble;
}

const _steps = [
  _TutorialStep(
    art: _Art.look,
    title: 'Scopri i drop',
    body:
        'Muovi la mappa: quando il mirino al centro si illumina, '
        'sei vicino a un drop da scoprire.',
    target: Alignment(0, -0.06),
    bubble: Alignment(0, 0.42),
  ),
  _TutorialStep(
    art: _Art.colors,
    title: 'Ogni colore ha un senso',
    body:
        'Rosa la tua cerchia, ambra i drop pubblici, bianco i tuoi. '
        'Filtra per vedere solo quello che ti interessa.',
    target: Alignment(-0.55, -0.62),
    bubble: Alignment(0, -0.05),
  ),
  _TutorialStep(
    art: _Art.swipe,
    title: 'Scorri tra i drop',
    body:
        'Scorri le card di lato per passare al drop vicino successivo. '
        'Toccane una per aprirla.',
    target: Alignment(-0.25, 0.66),
    bubble: Alignment(0, -0.2),
  ),
  _TutorialStep(
    art: _Art.drop,
    title: 'Lascia un drop',
    body: 'Tocca qui per lasciare un nuovo drop nel punto in cui ti trovi.',
    target: Alignment(0.88, 0.63),
    bubble: Alignment(0, -0.05),
  ),
];

class MapTutorialOverlay extends StatefulWidget {
  const MapTutorialOverlay({
    super.key,
    required this.onDone,
    required this.targets,
  });
  final VoidCallback onDone;

  /// Centro reale sullo schermo del bersaglio di ogni passo (indice → punto),
  /// misurato dai widget veri.
  final Map<int, Offset> targets;

  @override
  State<MapTutorialOverlay> createState() => _MapTutorialOverlayState();
}

class _MapTutorialOverlayState extends State<MapTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;

  // Fa scorrere la scia di puntini e pulsare il bersaglio.
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onDone();
    }
  }

  void _previous() {
    if (_step > 0) setState(() => _step--);
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -250) {
      _next();
    } else if (velocity > 250) {
      _previous();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final step = _steps[_step];

    Offset resolve(Alignment a) =>
        Offset((a.x + 1) / 2 * size.width, (a.y + 1) / 2 * size.height);

    final targetPoint = widget.targets[_step] ?? resolve(step.target);
    final bubbleTop = ((step.bubble.y + 1) / 2 * size.height - 110).clamp(
      pad.top + 64,
      size.height - 330,
    );
    // La scia parte dal bordo della card più vicino al bersaglio.
    final bubbleCenterY = bubbleTop + 110;
    final from = Offset(
      size.width / 2,
      targetPoint.dy < bubbleCenterY ? bubbleTop - 6 : bubbleTop + 226,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Velo scuro: tocca per andare avanti, scorri per cambiare passo.
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              onHorizontalDragEnd: _onSwipeEnd,
              child: ColoredBox(color: AppColors.ink.withValues(alpha: 0.5)),
            ),
          ),

          // Scia di puntini + bersaglio pulsante.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flow,
                builder: (_, _) => CustomPaint(
                  painter: _DotTrailPainter(
                    from: from,
                    to: targetPoint,
                    phase: _flow.value,
                  ),
                ),
              ),
            ),
          ),

          // Card del passo.
          AnimatedPositioned(
            duration: AppMotion.mingle,
            curve: AppMotion.mingleCurve,
            left: 20,
            right: 20,
            top: bubbleTop,
            child: GestureDetector(
              onHorizontalDragEnd: _onSwipeEnd,
              child: AnimatedSwitcher(
                duration: AppMotion.pop,
                switchInCurve: AppMotion.popCurve,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: .94, end: 1.0).animate(a),
                    child: child,
                  ),
                ),
                child: _TutorialCard(
                  key: ValueKey(_step),
                  step: step,
                  index: _step,
                  onNext: _next,
                ),
              ),
            ),
          ),

          // Salta
          Positioned(
            top: pad.top + 12,
            right: 12,
            child: TextButton(
              onPressed: widget.onDone,
              style: TextButton.styleFrom(foregroundColor: AppColors.paper),
              child: const Text('Salta'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────────

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    super.key,
    required this.step,
    required this.index,
    required this.onNext,
  });

  final _TutorialStep step;
  final int index;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLast = index == _steps.length - 1;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderDark),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 84,
                width: double.infinity,
                child: Center(child: _StepArt(art: step.art)),
              ),
              const SizedBox(height: 10),
              Text(
                step.title,
                style: AppTextStyles.headline(
                  context,
                ).copyWith(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                step.body,
                style: AppTextStyles.body(context).copyWith(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    AnimatedContainer(
                      duration: AppMotion.pop,
                      curve: AppMotion.popCurve,
                      width: i == index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= index
                            ? AppColors.accent
                            : AppColors.darkSurfaceHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        isLast ? 'Ho capito' : 'Avanti',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Illustrazioni dei passi ─────────────────────────────────────────────────

class _StepArt extends StatefulWidget {
  const _StepArt({required this.art});
  final _Art art;

  @override
  State<_StepArt> createState() => _StepArtState();
}

class _StepArtState extends State<_StepArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.art) {
      _Art.drop => const DropEcho(size: 92, loop: true),
      _ => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => switch (widget.art) {
          _Art.look => _look(_c.value),
          _Art.colors => _colors(_c.value),
          _ => _swipe(_c.value),
        },
      ),
    };
  }

  /// Dot che cerca intorno con lo sguardo, dentro un mirino.
  Widget _look(double t) {
    final a = t * math.pi * 2;
    final found = t > .7 && t < .9;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: found
                  ? AppColors.accent
                  : AppColors.paper.withValues(alpha: .25),
              width: 2,
            ),
          ),
        ),
        MingleDot(
          size: 58,
          face: found ? DotFace.love : DotFace.happy,
          look: found ? Offset.zero : Offset(math.cos(a), math.sin(a * 2) * .5),
        ),
      ],
    );
  }

  /// I tre colori della mappa: tre Dot che saltano a turno.
  Widget _colors(double t) {
    Widget dot(Color c, String label, int i) {
      final ph = (t * 3 - i) % 3;
      final hop = ph < 1 ? math.sin(ph * math.pi) : 0.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: Offset(0, -hop * 12),
            child: MingleDot(size: 46, color: c, wobble: .05),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: AppColors.paper.withValues(alpha: .8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(AppColors.accent, 'Cerchia', 0),
        const SizedBox(width: 18),
        dot(AppColors.accentSecondary, 'Pubblici', 1),
        const SizedBox(width: 18),
        dot(AppColors.paper, 'Tuoi', 2),
      ],
    );
  }

  /// Due card che scorrono di lato, Dot che guarda la nuova.
  Widget _swipe(double t) {
    // 0–.35 fermo, .35–.65 scorre, .65–1 fermo sulla nuova.
    final k = Curves.easeInOutCubic.transform(((t - .35) / .3).clamp(0, 1));
    Widget card(Color c, double dx) => Transform.translate(
      offset: Offset(dx, 0),
      child: Container(
        width: 74,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: .7), width: 2),
        ),
        alignment: Alignment.center,
        child: MingleDot(size: 30, color: c, showFace: false),
      ),
    );
    return SizedBox(
      width: 220,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card(AppColors.accentSecondary, 90 - k * 90),
          card(AppColors.accent, -k * 90),
          Positioned(
            bottom: 0,
            child: Transform.translate(
              offset: Offset(30 - k * 30, 0),
              child: Icon(
                Icons.swipe_left_rounded,
                size: 22,
                color: AppColors.paper.withValues(alpha: .7 * (1 - k) + .2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scia di puntini ─────────────────────────────────────────────────────────

/// Puntini che scorrono lungo una curva morbida dalla card al bersaglio,
/// più grandi man mano che si avvicinano, e un Dot magenta che pulsa
/// sul bersaglio. Niente sfumature.
class _DotTrailPainter extends CustomPainter {
  const _DotTrailPainter({
    required this.from,
    required this.to,
    required this.phase,
  });

  final Offset from;
  final Offset to;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final delta = to - from;
    final len = delta.distance;
    if (len < 30) return;
    final mid = Offset.lerp(from, to, .5)!;
    final normal = Offset(-delta.dy, delta.dx) / len;
    final control = mid + normal * (len * .18);

    Offset at(double t) {
      final u = 1 - t;
      return from * (u * u) + control * (2 * u * t) + to * (t * t);
    }

    // Puntini (si fermano prima del bersaglio, per lasciare spazio all'anello).
    const gap = 16.0;
    final n = (len / gap).floor();
    final stop = 1 - 30 / len;
    for (var i = 0; i < n; i++) {
      final t = ((i + phase) / n) * stop;
      final r = 2.0 + 2.2 * t;
      canvas.drawCircle(
        at(t),
        r,
        Paint()..color = AppColors.paper.withValues(alpha: .35 + .6 * t),
      );
    }

    // Bersaglio: anello che si allarga + punto magenta pieno.
    final p = phase;
    canvas.drawCircle(
      to,
      22 + 16 * p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.accent.withValues(alpha: .9 * (1 - p)),
    );
    canvas.drawCircle(
      to,
      24,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_DotTrailPainter old) =>
      old.phase != phase || old.from != from || old.to != to;
}
