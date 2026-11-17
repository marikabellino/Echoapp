import 'dart:math' as math;

import 'package:echo/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Le espressioni di Dot. Il colore non dipende dall'espressione: di default
/// Dot è magenta, e si può cambiare con `color`.
enum DotFace { happy, love, wink, sleepy, dizzy, yum }

extension DotFaceX on DotFace {
  /// Assonnato respira lento, goloso è agitato.
  double get speed => switch (this) {
    DotFace.sleepy => 0.45,
    DotFace.yum => 1.6,
    _ => 1.0,
  };
}

/// Dot — la mascotte di mingle.
///
/// Un blob vivo che respira (bordo ondulato), sbatte le palpebre e può
/// guardare in una direzione con [look] (offset normalizzato -1..1).
/// Con [showFace] = false resta solo il "punto", utile come segnaposto.
class MingleDot extends StatefulWidget {
  const MingleDot({
    super.key,
    this.size = 64,
    this.face = DotFace.happy,
    this.color,
    this.look = Offset.zero,
    this.showFace = true,
    this.wobble = 0.04,
  });

  final double size;
  final DotFace face;

  /// Colore del corpo (default: magenta del brand).
  final Color? color;
  final Offset look;
  final bool showFace;
  final double wobble;

  @override
  State<MingleDot> createState() => _MingleDotState();
}

class _MingleDotState extends State<MingleDot>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final double _seed = math.Random().nextDouble() * 6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RepaintBoundary(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: widget.color ?? AppColors.accent),
        duration: const Duration(milliseconds: 450),
        builder: (context, c, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _DotPainter(
            time: _time,
            seed: _seed,
            color: c ?? AppColors.accent,
            face: widget.face,
            look: widget.look,
            showFace: widget.showFace,
            wobble: still ? 0 : widget.wobble,
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.time,
    required this.seed,
    required this.color,
    required this.face,
    required this.look,
    required this.showFace,
    required this.wobble,
  }) : super(repaint: time);

  final ValueNotifier<double> time;
  final double seed;
  final Color color;
  final DotFace face;
  final Offset look;
  final bool showFace;
  final double wobble;

  static const _ink = AppColors.darkBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value * face.speed;
    canvas.save();
    // Tutto il disegno è in uno spazio 200×200, centro (100,100), raggio 70.
    canvas.scale(size.width / 200);

    // ── Corpo ondulato ─────────────────────────────────────────────────
    final body = Path();
    const n = 72;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final k =
          1 +
          wobble *
              (0.55 * math.sin(3 * a + t * 1.4 + seed) +
                  0.35 * math.sin(5 * a - t * 1.1 + seed * 2) +
                  0.25 * math.sin(2 * a + t * 0.8));
      final p = Offset(100 + math.cos(a) * 70 * k, 100 + math.sin(a) * 70 * k);
      i == 0 ? body.moveTo(p.dx, p.dy) : body.lineTo(p.dx, p.dy);
    }
    body.close();
    canvas.drawPath(body, Paint()..color = color);

    if (showFace) _paintFace(canvas, time.value);
    canvas.restore();
  }

  void _paintFace(Canvas canvas, double t) {
    final ink = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cheek = Paint()..color = Colors.white.withValues(alpha: 0.24);
    final lk = Offset(look.dx.clamp(-1, 1) * 8, look.dy.clamp(-1, 1) * 8);

    // Blink ogni ~4,2 s (sfasato col seed): scala verticale degli occhi.
    final phase = (t + seed) % 4.2;
    final blink = phase > 3.93 && phase < 4.03
        ? 0.08 + (phase - 3.98).abs() / 0.05 * 0.92
        : 1.0;

    void eyes(List<Offset> centers, {double rx = 8, double ry = 11}) {
      for (final c in centers) {
        final cc = c + lk;
        canvas.drawOval(
          Rect.fromCenter(center: cc, width: rx * 2, height: ry * 2 * blink),
          ink,
        );
        if (blink > 0.5) {
          canvas.drawCircle(
            cc + const Offset(3, -5),
            2.6,
            Paint()..color = Colors.white,
          );
        }
      }
    }

    Path arc(Offset a, Offset ctrl, Offset b) => Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);

    void heart(Offset c, double s) {
      final p = Path()
        ..moveTo(0, 9)
        ..cubicTo(-16, -2, -12, -16, 0, -8)
        ..cubicTo(12, -16, 16, -2, 0, 9)
        ..close();
      canvas.save();
      canvas.translate(c.dx + lk.dx, c.dy + lk.dy);
      canvas.scale(s);
      canvas.drawPath(p, ink);
      canvas.restore();
    }

    void cheeks() {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(62, 110), width: 18, height: 10),
        cheek,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(138, 110), width: 18, height: 10),
        cheek,
      );
    }

    switch (face) {
      case DotFace.happy:
        eyes(const [Offset(80, 92), Offset(120, 92)]);
        canvas.drawPath(
          arc(const Offset(87, 116), const Offset(100, 128), const Offset(113, 116)),
          stroke,
        );
        cheeks();
      case DotFace.love:
        heart(const Offset(78, 92), 1.25);
        heart(const Offset(122, 92), 1.25);
        canvas.drawPath(
          arc(const Offset(84, 118), const Offset(100, 130), const Offset(116, 118)),
          stroke,
        );
        cheeks();
      case DotFace.wink:
        eyes(const [Offset(80, 92)]);
        canvas.drawPath(
          arc(const Offset(112, 93) + lk, const Offset(122, 85) + lk,
              const Offset(132, 93) + lk),
          stroke,
        );
        canvas.drawPath(
          arc(const Offset(90, 122), const Offset(100, 118), const Offset(112, 120)),
          stroke,
        );
        // Ditino "shh"
        canvas.save();
        canvas.translate(100, 120);
        canvas.rotate(-0.14);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-3.5, -12, 7, 24),
            const Radius.circular(3.5),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.9),
        );
        canvas.restore();
      case DotFace.sleepy:
        canvas.drawPath(
          arc(const Offset(70, 94), const Offset(80, 102), const Offset(90, 94)),
          stroke,
        );
        canvas.drawPath(
          arc(const Offset(110, 94), const Offset(120, 102), const Offset(130, 94)),
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(100, 122), width: 12, height: 14),
          ink,
        );
      case DotFace.dizzy:
        final white = Paint()..color = Colors.white;
        canvas.drawCircle(const Offset(78, 92), 13, white);
        canvas.drawCircle(const Offset(122, 92), 13, white);
        canvas.drawCircle(const Offset(72, 96) + lk * 0.4, 6, ink);
        canvas.drawCircle(const Offset(126, 86) + lk * 0.4, 6, ink);
        final wave = Path()..moveTo(82, 124);
        for (var i = 0; i < 3; i++) {
          final x = 82.0 + i * 12;
          wave.quadraticBezierTo(x + 3, i.isEven ? 117 : 131, x + 6, 124);
          wave.quadraticBezierTo(x + 9, i.isEven ? 131 : 117, x + 12, 124);
        }
        canvas.drawPath(wave, stroke..strokeWidth = 5);
      case DotFace.yum:
        for (final x in [68.0, 112.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 98)
              ..lineTo(x + 10, 86)
              ..lineTo(x + 20, 98),
            stroke,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(82, 112)
            ..quadraticBezierTo(100, 140, 118, 112)
            ..close(),
          ink,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(104, 126), width: 14, height: 10),
          Paint()..color = AppColors.blush,
        );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color ||
      old.face != face ||
      old.look != look ||
      old.showFace != showFace ||
      old.wobble != wobble;
}
