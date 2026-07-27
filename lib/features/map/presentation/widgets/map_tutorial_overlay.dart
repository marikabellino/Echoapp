import 'dart:math' as math;
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.target,
    required this.bubble,
    required this.bubbleAlign,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Where on screen the highlighted element sits (-1..1 in each axis).
  final Alignment target;

  /// Where the text bubble sits (-1..1 in each axis).
  final Alignment bubble;

  /// Which corner of the bubble the text should hang from.
  final CrossAxisAlignment bubbleAlign;
}

const _steps = [
  _TutorialStep(
    icon: Icons.explore_outlined,
    title: 'Scopri i drop',
    body:
        'Muovi la mappa: quando il mirino al centro si illumina, '
        'sei vicino a un drop da scoprire.',
    target: Alignment(0, -0.06),
    bubble: Alignment(0, 0.30),
    bubbleAlign: CrossAxisAlignment.center,
  ),
  _TutorialStep(
    icon: Icons.tune_rounded,
    title: 'Filtra la vista',
    body: 'Scegli se vedere i drop della tua cerchia o quelli pubblici.',
    target: Alignment(-0.55, -0.62),
    bubble: Alignment(-0.05, -0.30),
    bubbleAlign: CrossAxisAlignment.start,
  ),
  _TutorialStep(
    icon: Icons.swipe_up_alt_outlined,
    title: 'Scorri tra i drop',
    body:
        'Trascina la card verso l\'alto per passare '
        'al prossimo drop vicino, come in un feed.',
    target: Alignment(-0.25, 0.66),
    bubble: Alignment(-0.15, -0.15),
    bubbleAlign: CrossAxisAlignment.start,
  ),
  _TutorialStep(
    icon: Icons.add_circle_outline,
    title: 'Lascia un drop',
    body: 'Tocca qui per lasciare un nuovo drop nel punto in cui ti trovi.',
    target: Alignment(0.88, 0.63),
    bubble: Alignment(0.15, 0.35),
    bubbleAlign: CrossAxisAlignment.end,
  ),
];

/// First-run guided tour for the map screen: a translucent overlay with
/// soft, brightly-colored arrows pointing at each piece of the UI in turn.
class MapTutorialOverlay extends StatefulWidget {
  const MapTutorialOverlay({
    super.key,
    required this.onDone,
    required this.targets,
  });
  final VoidCallback onDone;

  /// Real on-screen center point for each step's target, measured from the
  /// actual widgets (step index → screen position).
  final Map<int, Offset> targets;

  @override
  State<MapTutorialOverlay> createState() => _MapTutorialOverlayState();
}

class _MapTutorialOverlayState extends State<MapTutorialOverlay> {
  int _step = 0;

  void _next() {
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
    final size = MediaQuery.of(context).size;
    final step = _steps[_step];

    Offset resolve(Alignment a) =>
        Offset((a.x + 1) / 2 * size.width, (a.y + 1) / 2 * size.height);

    final targetPoint = widget.targets[_step] ?? resolve(step.target);
    final bubblePoint = resolve(step.bubble);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: ValueKey(_step),
        children: [
          // Translucent scrim — tap to advance, swipe left/right to move
          // between steps.
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              onHorizontalDragEnd: _onSwipeEnd,
              child: Container(color: Colors.black.withValues(alpha: 0.22)),
            ),
          ),

          // Pulsing highlight ring on the target.
          Positioned(
            left: targetPoint.dx - 34,
            top: targetPoint.dy - 34,
            child: IgnorePointer(
              child:
                  Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.85),
                            width: 2,
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .scale(
                        duration: 1100.ms,
                        begin: const Offset(0.7, 0.7),
                        end: const Offset(1.15, 1.15),
                        curve: Curves.easeOut,
                      )
                      .fadeOut(duration: 1100.ms, curve: Curves.easeOut),
            ),
          ),

          // Soft curved arrow from bubble to target.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SoftArrowPainter(from: bubblePoint, to: targetPoint),
              ),
            ),
          ),

          // Text bubble.
          Positioned(
            left: 24,
            right: 24,
            top: (bubblePoint.dy - 60).clamp(
              MediaQuery.of(context).padding.top + 16,
              size.height - 220,
            ),
            child: Align(
              alignment: step.bubbleAlign == CrossAxisAlignment.start
                  ? Alignment.centerLeft
                  : step.bubbleAlign == CrossAxisAlignment.end
                  ? Alignment.centerRight
                  : Alignment.center,
              child: GestureDetector(
                onHorizontalDragEnd: _onSwipeEnd,
                child: _TutorialBubble(step: step, onNext: _next, index: _step),
              ),
            ),
          ),

          // Skip button, top-right.
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 20,
            child: GestureDetector(
              onTap: widget.onDone,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Text(
                  'Salta',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _TutorialBubble extends StatelessWidget {
  const _TutorialBubble({
    required this.step,
    required this.onNext,
    required this.index,
  });

  final _TutorialStep step;
  final VoidCallback onNext;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isLast = index == _steps.length - 1;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 0.75,
              ),
            ),
            child: Column(
              crossAxisAlignment: step.bubbleAlign,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.accent, AppColors.accentSecondary],
                        ),
                      ),
                      child: Icon(step.icon, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.body,
                  textAlign: step.bubbleAlign == CrossAxisAlignment.center
                      ? TextAlign.center
                      : TextAlign.start,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < _steps.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 5),
                        width: i == index ? 16 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: i == index
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onNext,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.accent,
                              AppColors.accentSecondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        
                        child: Text(
                          isLast ? 'Fatto' : 'Avanti',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

/// Draws a soft, curved, gradient-colored arrow with a small arrowhead —
/// playful rather than a straight technical line.
class _SoftArrowPainter extends CustomPainter {
  const _SoftArrowPainter({required this.from, required this.to});
  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = Offset.lerp(from, to, 0.5)!;
    final delta = to - from;
    final normal = Offset(-delta.dy, delta.dx);
    final normalLen = normal.distance;
    final control = normalLen == 0
        ? mid
        : mid + normal / normalLen * (delta.distance * 0.22);

    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    final gradient = LinearGradient(
      colors: [
        AppColors.accent.withValues(alpha: 0.9),
        AppColors.accentSecondary.withValues(alpha: 0.9),
      ],
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(Rect.fromPoints(from, to));

    canvas.drawPath(path, paint);

    // Arrowhead pointing along the curve's end tangent.
    final tangent = (to - control);
    final angle = math.atan2(tangent.dy, tangent.dx);
    const headLength = 11.0;
    const headAngle = 0.5;
    final p1 =
        to -
        Offset(math.cos(angle - headAngle), math.sin(angle - headAngle)) *
            headLength;
    final p2 =
        to -
        Offset(math.cos(angle + headAngle), math.sin(angle + headAngle)) *
            headLength;

    final headPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.accentSecondary.withValues(alpha: 0.95);
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      headPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SoftArrowPainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
}
