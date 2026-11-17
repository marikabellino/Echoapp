import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/shared/widgets/brand/goo.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Splash di mingle. (≈3,2 s — i tempi sotto sono "di progetto" e vengono
/// rallentati di [_slow]).
///
///  0 ms    sei Dot, uno per mood, entrano dai bordi
///  650 ms  si fondono nel punto (effetto "goo": blur + soglia alpha)
///  1150 ms le lettere escono da Dot verso sinistra, dalla "e" alla "m"
///  1750 ms Dot apre gli occhi, compare il payoff
///
/// [onFinished] viene chiamato a fine sequenza.
class MingleSplash extends StatefulWidget {
  const MingleSplash({super.key, this.onFinished, this.fontSize = 52});

  final VoidCallback? onFinished;
  final double fontSize;

  @override
  State<MingleSplash> createState() => _MingleSplashState();
}

class _MingleSplashState extends State<MingleSplash>
    with SingleTickerProviderStateMixin {
  /// Tempi di progetto (ms) → durata reale moltiplicata per [_slow].
  static const _designMs = 2300.0;
  static const _slow = 1.4;
  static final _total = Duration(milliseconds: (_designMs * _slow).round());
  late final AnimationController _c;

  // Ordine di arrivo: il magenta (drop) arriva per ultimo e resta.
  static const _order = [
    DotMood.love,
    DotMood.secret,
    DotMood.dream,
    DotMood.lost,
    DotMood.food,
    DotMood.drop,
  ];
  // Punti di partenza, in frazioni della dimensione dello schermo
  // rispetto al punto d'arrivo.
  static const _starts = [
    Offset(-0.75, -0.35),
    Offset(0.75, -0.42),
    Offset(-0.35, 0.65),
    Offset(0.75, 0.40),
    Offset(-0.75, 0.20),
    Offset(0.30, -0.70),
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
        widget.onFinished?.call();
      } else {
        _c.forward().whenComplete(() => widget.onFinished?.call());
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _iv(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  double get _ms => _c.value * _designMs;
  double _at(double startMs, double durMs, [Curve curve = Curves.linear]) =>
      curve.transform(((_ms - startMs) / durMs).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final fs = widget.fontSize;
    final dotSize = fs * 0.44;
    final style = GoogleFonts.oi(
      fontSize: fs,
      height: 1,
      color: AppColors.textLight,
    );
    const word = 'mingle';

    return ColoredBox(
      color: AppColors.darkBackground,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final faceIn = _at(1750, 220);
          final tagIn = _at(1850, 500, Curves.easeOut);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < word.length; i++)
                    _letter(word[i], style, word.length - 1 - i, fs),
                  SizedBox(width: fs * 0.03),
                  Padding(
                    padding: EdgeInsets.only(bottom: fs * 0.04),
                    child: SizedBox.square(
                      dimension: dotSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          OverflowBox(
                            maxWidth: screen.width * 2,
                            maxHeight: screen.height * 2,
                            child: Goo(
                              child: CustomPaint(
                                size: Size(screen.width * 2, screen.height * 2),
                                painter: _GooPainter(_gooDots(screen, dotSize)),
                              ),
                            ),
                          ),
                          if (faceIn > 0)
                            Opacity(
                              opacity: faceIn,
                              child: MingleDot(size: dotSize, wobble: 0.03),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: fs * 0.35),
              Opacity(
                opacity: tagIn,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - tagIn)),
                  child: Text(
                    'LASCIA IL SEGNO',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      letterSpacing: 1.8,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Ogni lettera "esce" da Dot: parte schiacciata sul punto e scatta in
  /// posizione con una molla. [k] = distanza in lettere dal punto.
  Widget _letter(String ch, TextStyle style, int k, double fs) {
    final p = _at(1150 + k * 55.0, 620, Curves.easeOutBack);
    final dx = (k + 0.9) * fs * 0.78 * (1 - p);
    return Opacity(
      opacity: _at(1150 + k * 55.0, 120),
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.scale(
          scale: 0.1 + 0.9 * p,
          alignment: Alignment.bottomCenter,
          child: Text(ch, style: style),
        ),
      ),
    );
  }

  List<_Goo> _gooDots(Size screen, double dotSize) {
    final r = dotSize / 2;
    final out = <_Goo>[];
    for (var i = 0; i < _order.length; i++) {
      final mood = _order[i];
      final fly = _iv(i * 0.03, i * 0.03 + 0.30, Curves.easeInOutCubic);
      final s = _starts[i];
      final from = Offset(s.dx * screen.width, s.dy * screen.height);
      // Leggera curva: il punto passa per un "mid" spostato di lato.
      final side = Offset(i.isEven ? -30 : 30, 0) * (fly * (1 - fly) * 4);
      final pos = Offset.lerp(from, Offset.zero, fly)! + side;

      double radius;
      if (mood == DotMood.drop) {
        // Si gonfia mentre ingloba gli altri, poi rimbalza alla misura finale.
        final grow = _at(650, 300, Curves.easeOut);
        final settle = _at(1050, 520, Curves.elasticOut);
        radius = r * (1.9 + 0.35 * grow - (1.25 * settle));
      } else {
        radius = r * 1.5 * (1 - _at(980 + i * 20.0, 380, Curves.easeIn));
      }
      out.add(_Goo(pos, radius, mood.color));
    }
    return out;
  }
}

class _Goo {
  const _Goo(this.offset, this.radius, this.color);
  final Offset offset;
  final double radius;
  final Color color;
}

class _GooPainter extends CustomPainter {
  _GooPainter(this.dots);
  final List<_Goo> dots;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final d in dots) {
      if (d.radius <= 0.5) continue;
      canvas.drawCircle(c + d.offset, d.radius, Paint()..color = d.color);
    }
  }

  @override
  bool shouldRepaint(_GooPainter old) => true;
}
