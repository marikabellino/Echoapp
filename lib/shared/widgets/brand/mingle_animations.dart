import 'dart:math' as math;

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/shared/widgets/brand/goo.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

// Libreria animazioni del brand mingle. — vedi docs/brand/mingle-brand-kit.html
//
//  MingleWordmark   logo "mingle." con le lettere che rimbalzano e Dot vivo
//  MingleLogomark   due Dot che si fondono (loop)
//  MingleLoader     loader gommoso (sostituisce lo spinner)
//  MingleDotsLoader tre puntini gommosi per pulsanti e spazi stretti
//  DropEcho         Dot cade e lascia onde d'eco (pubblicazione drop)
//  LikeBurst        squash + occhi a cuore + coriandoli (doppio tap)
//  MinglePin        Dot a forma di pin con badge
//  MingleAppIcon    icona app animata
//  MingleMarquee    nastro di testo che scorre

const _ink = AppColors.darkBackground;
const _paper = AppColors.textLight;

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 0→1→0 su un ciclo [0,1].
double _tri(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;

double _seg(double t, double a, double b, [Curve c = Curves.linear]) =>
    c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

// ═══════════════════════════════════════════════════════════════════════════
// WORDMARK
// ═══════════════════════════════════════════════════════════════════════════

/// Il logo "mingle." con Dot al posto del punto.
///
/// Con [animate] le lettere entrano una dopo l'altra con una molla e poi Dot
/// cade dall'alto e rimbalza. Toccando Dot (se [interactive]) fa uno squash
/// e spara tanti piccoli Dot tutto intorno.
class MingleWordmark extends StatefulWidget {
  const MingleWordmark({
    super.key,
    this.fontSize = 42,
    this.color = _paper,
    this.dotColor,
    this.animate = true,
    this.interactive = true,
    this.delay = Duration.zero,
  });

  final double fontSize;
  final Color color;
  final Color? dotColor;
  final bool animate;
  final bool interactive;
  final Duration delay;

  @override
  State<MingleWordmark> createState() => _MingleWordmarkState();
}

class _MingleWordmarkState extends State<MingleWordmark>
    with TickerProviderStateMixin {
  static const _word = 'mingle';
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.animate || _reduceMotion(context)) {
        _intro.value = 1;
      } else {
        Future.delayed(widget.delay, () {
          if (mounted) _intro.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _tapDot() {
    if (_reduceMotion(context)) return;
    _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.fontSize;
    final dotSize = fs * 0.46;
    final style = GoogleFonts.oi(fontSize: fs, height: 1, color: widget.color);

    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _burst]),
      builder: (context, _) {
        final ms = _intro.value * 2000;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _word.length; i++)
              _letter(_word[i], style, ms, i),
            SizedBox(width: fs * 0.02),
            Padding(
              padding: EdgeInsets.only(bottom: fs * 0.1),
              child: GestureDetector(
                onTap: widget.interactive ? _tapDot : null,
                behavior: HitTestBehavior.opaque,
                child: _dot(ms, dotSize),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _letter(String ch, TextStyle style, double ms, int i) {
    final p = Curves.easeOutBack.transform(
      ((ms - 50 - i * 70) / 900).clamp(0.0, 1.0),
    );
    final o = ((ms - 50 - i * 70) / 300).clamp(0.0, 1.0);
    return Opacity(
      opacity: o,
      child: Transform.translate(
        offset: Offset(0, widget.fontSize * 0.7 * (1 - p)),
        child: Transform.rotate(
          angle: 0.17 * (1 - p),
          child: Transform.scale(
            scale: 0.4 + 0.6 * p,
            alignment: Alignment.bottomCenter,
            child: Text(ch, style: style),
          ),
        ),
      ),
    );
  }

  Widget _dot(double ms, double size) {
    // Caduta con rimbalzi (stessi keyframe del brand kit).
    final t = ((ms - 750) / 1100).clamp(0.0, 1.0);
    double y, sx, sy;
    if (t < .45) {
      final k = Curves.easeIn.transform(t / .45);
      y = -2.6 * (1 - k);
      sx = .6 + .4 * k;
      sy = 1.3 - .3 * k;
      if (t > .4) {
        sx = 1.35;
        sy = .6;
      }
    } else if (t < .62) {
      final k = Curves.easeOut.transform((t - .45) / .17);
      y = -.38 * k;
      sx = 1.35 - .45 * k;
      sy = .6 + .52 * k;
    } else if (t < .78) {
      final k = Curves.easeIn.transform((t - .62) / .16);
      y = -.38 * (1 - k);
      sx = .9 + .22 * k;
      sy = 1.12 - .24 * k;
    } else {
      final k = Curves.easeOut.transform((t - .78) / .22);
      y = -.06 * math.sin(k * math.pi);
      sx = 1.12 - .12 * k;
      sy = .88 + .12 * k;
    }
    // Squash al tap
    final b = _burst.value;
    if (b > 0 && b < .45) {
      final s = math.sin(b / .45 * math.pi);
      sx *= 1 + .25 * s;
      sy *= 1 - .25 * s;
    }
    final dot = Transform.translate(
      offset: Offset(0, y * size),
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(sx, sy, 1),
        child: MingleDot(
          size: size,
          color: widget.dotColor,
          showFace: size >= 14,
        ),
      ),
    );
    if (b == 0 || b == 1) return Opacity(opacity: ms < 760 ? 0 : 1, child: dot);

    // Burst: piccoli Dot nei colori del brand escono e tornano dentro.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < 6; i++)
          Builder(
            builder: (_) {
              final a = i / 6 * math.pi * 2 - math.pi / 2;
              final out = b < .55
                  ? Curves.easeOutBack.transform(b / .55)
                  : 1 - Curves.easeIn.transform((b - .55) / .45);
              final d = size * 1.6 * out;
              return Transform.translate(
                offset: Offset(math.cos(a) * d, math.sin(a) * d),
                child: Opacity(
                  opacity: (1 - b).clamp(0.0, 1.0),
                  child: Container(
                    width: size * .32 * (0.6 + out * 0.6),
                    height: size * .32 * (0.6 + out * 0.6),
                    decoration: BoxDecoration(
                      color: const [
                        AppColors.accent,
                        AppColors.accentSecondary,
                        _paper,
                      ][i % 3],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
        dot,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOGOMARK — due Dot che si fondono
// ═══════════════════════════════════════════════════════════════════════════

class MingleLogomark extends StatefulWidget {
  const MingleLogomark({
    super.key,
    this.size = 120,
    this.left = AppColors.accent,
    this.right = AppColors.accentSecondary,
    this.faceColor = _ink,
  });

  final double size;
  final Color left;
  final Color right;
  final Color faceColor;

  @override
  State<MingleLogomark> createState() => _MingleLogomarkState();
}

class _MingleLogomarkState extends State<MingleLogomark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s * 1.5,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            // 0→40% si avvicinano, 40→60% fusi, 60→100% si separano.
            final near = t < .4
                ? Curves.easeInOutCubic.transform(t / .4)
                : t < .6
                ? 1.0
                : 1 - Curves.easeInOutCubic.transform((t - .6) / .4);
            final u = s / 240;
            final dx = (4 + 58 * (1 - near)) * u;
            final face = _seg(t, .38, .46) * (1 - _seg(t, .54, .62));
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Goo(
                    blur: 9 * u,
                    child: CustomPaint(
                      painter: _CirclesPainter([
                        (Offset(-dx, 0), 36 * u * 1.4, widget.left),
                        (Offset(dx, 0), 36 * u * 1.4, widget.right),
                      ]),
                    ),
                  ),
                ),
                Opacity(
                  opacity: face,
                  child: Transform.scale(
                    scale: .4 + .6 * face,
                    child: CustomPaint(
                      size: Size.square(s * .3),
                      painter: _MiniFacePainter(widget.faceColor),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CirclesPainter extends CustomPainter {
  _CirclesPainter(this.circles);
  final List<(Offset, double, Color)> circles;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final (o, r, color) in circles) {
      if (r > .3) canvas.drawCircle(c + o, r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_CirclesPainter old) => true;
}

class _MiniFacePainter extends CustomPainter {
  _MiniFacePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 40;
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(10 * u, 14 * u), 4.5 * u, p);
    canvas.drawCircle(Offset(30 * u, 14 * u), 4.5 * u, p);
    canvas.drawPath(
      Path()
        ..moveTo(10 * u, 27 * u)
        ..quadraticBezierTo(20 * u, 35 * u, 30 * u, 27 * u),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MiniFacePainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// LOADER GOMMOSO
// ═══════════════════════════════════════════════════════════════════════════

/// Sostituisce `CircularProgressIndicator`: tre Dot orbitano attorno a un
/// Dot magenta e si fondono con lui al centro, a ritmo continuo.
class MingleLoader extends StatefulWidget {
  const MingleLoader({super.key, this.size = 56});

  final double size;

  @override
  State<MingleLoader> createState() => _MingleLoaderState();
}

class _MingleLoaderState extends State<MingleLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  static const _orbs = [
    AppColors.accentSecondary,
    AppColors.paper,
    AppColors.blush,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final u = s / 120;
    return Semantics(
      label: 'Caricamento',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: s,
          child: Goo(
            blur: math.max(2.5, 9 * u),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = _c.value;
                final circles = <(Offset, double, Color)>[
                  (Offset.zero, 22 * u, AppColors.accent),
                ];
                for (var i = 0; i < 3; i++) {
                  final phase = (t + i / 3) % 1;
                  final inward = Curves.easeInOutCubic.transform(_tri(phase));
                  final dist = (4 + 42 * (1 - inward)) * u;
                  final a = t * math.pi * 2 + i * math.pi * 2 / 3;
                  circles.add((
                    Offset(math.sin(a) * dist, -math.cos(a) * dist),
                    18 * u,
                    _orbs[i],
                  ));
                }
                return CustomPaint(
                  size: Size.square(s),
                  painter: _CirclesPainter(circles),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Versione piccola del loader: tre Dot che saltano in onda e si toccano
/// come gocce. Va dentro i pulsanti e nei punti stretti (al posto degli
/// spinner da 16–22 px).
class MingleDotsLoader extends StatefulWidget {
  const MingleDotsLoader({super.key, this.size = 20, this.color = _paper});

  /// Altezza: la larghezza è circa 2,6×.
  final double size;
  final Color color;

  @override
  State<MingleDotsLoader> createState() => _MingleDotsLoaderState();
}

class _MingleDotsLoaderState extends State<MingleDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size;
    final w = h * 2.6;
    final r = h * .2;
    return Semantics(
      label: 'Caricamento',
      child: SizedBox(
        width: w,
        height: h,
        child: Goo(
          blur: math.max(1.2, h * .12),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final circles = <(Offset, double, Color)>[];
              for (var i = 0; i < 3; i++) {
                final ph = (_c.value - i * .16) % 1;
                final jump = ph < .5 ? math.sin(ph / .5 * math.pi) : 0.0;
                // Si stringono verso il centro mentre saltano: si toccano.
                final x = (i - 1) * h * (.62 - .14 * jump);
                circles.add((
                  Offset(x, -jump * h * .28),
                  r * (1 + .15 * jump),
                  widget.color,
                ));
              }
              return CustomPaint(
                size: Size(w, h),
                painter: _CirclesPainter(circles),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DROP & ECO
// ═══════════════════════════════════════════════════════════════════════════

/// Dot cade sulla mappa, si schiaccia e lascia tre onde d'eco.
/// Con [loop] = false gioca una volta (≈1,7 s), sfuma e chiama [onDone].
class DropEcho extends StatefulWidget {
  const DropEcho({
    super.key,
    this.size = 180,
    this.color = AppColors.accent,
    this.loop = false,
    this.onDone,
  });

  final double size;
  final Color color;
  final bool loop;
  final VoidCallback? onDone;

  @override
  State<DropEcho> createState() => _DropEchoState();
}

class _DropEchoState extends State<DropEcho>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.loop ? 2600 : 1900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.loop) {
      _c.repeat();
    } else {
      _c.forward().whenComplete(() => widget.onDone?.call());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dot = s * .34;
    final ground = s * .72;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          // caduta 0–.3, squash .3–.42, rimbalzo .42–.56, assestamento
          double y = 0, sx = 1, sy = 1;
          if (t < .3) {
            final k = Curves.easeIn.transform(t / .3);
            y = -(ground + dot) * (1 - k);
            sx = .82 + .1 * k;
            sy = 1.18 - .1 * k;
          } else if (t < .42) {
            final k = math.sin((t - .3) / .12 * math.pi);
            sx = 1 + .4 * k;
            sy = 1 - .4 * k;
          } else if (t < .56) {
            final k = math.sin((t - .42) / .14 * math.pi);
            y = -dot * .55 * k;
            sx = 1 - .08 * k;
            sy = 1 + .1 * k;
          } else if (t < .64) {
            final k = math.sin((t - .56) / .08 * math.pi);
            sx = 1 + .12 * k;
            sy = 1 - .12 * k;
          }
          final fade = widget.loop ? 1.0 : 1 - _seg(t, .82, 1);
          return Opacity(
            opacity: fade,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EchoPainter(
                      t: t,
                      ground: ground,
                      dotR: dot / 2,
                      color: widget.color,
                      lift: -y / (ground + dot),
                    ),
                  ),
                ),
                Positioned(
                  left: (s - dot) / 2,
                  top: ground - dot,
                  child: Transform.translate(
                    offset: Offset(0, y),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(sx, sy, 1),
                      child: MingleDot(size: dot, color: widget.color),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EchoPainter extends CustomPainter {
  _EchoPainter({
    required this.t,
    required this.ground,
    required this.dotR,
    required this.color,
    required this.lift,
  });

  final double t, ground, dotR, lift;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, ground - 2);
    // Ombra: piccola quando Dot è in aria.
    final sh = (1 - lift.clamp(0.0, 1.0));
    canvas.drawOval(
      Rect.fromCenter(center: c, width: dotR * 2.2 * sh, height: dotR * .5 * sh),
      Paint()
        ..color = Colors.black.withValues(alpha: .45 * sh)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Tre onde d'eco dal punto d'impatto.
    const colors = [null, null, AppColors.accentSecondary];
    for (var i = 0; i < 3; i++) {
      final p = _seg(t, .3 + i * .07, .3 + i * .07 + .5, Curves.easeOutCubic);
      if (p <= 0 || p >= 1) continue;
      final r = dotR * (.6 + 2.8 * p);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 2, height: r * .7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 - i * .7
          ..color = (colors[i] ?? color).withValues(alpha: .9 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_EchoPainter old) => true;
}

/// Mostra [DropEcho] a tutto schermo sopra l'app (es. dopo la pubblicazione).
void showDropEcho(BuildContext context, {Color color = AppColors.accent}) {
  if (_reduceMotion(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: Center(
        child: DropEcho(
          size: 220,
          color: color,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

// ═══════════════════════════════════════════════════════════════════════════
// LIKE BURST
// ═══════════════════════════════════════════════════════════════════════════

/// Doppio tap: Dot "love" spunta, si schiaccia, sparge coriandoli e
/// lascia salire un cuore. Gioca una volta al montaggio: per ripeterlo usa
/// una nuova `key`.
class LikeBurst extends StatefulWidget {
  const LikeBurst({super.key, this.size = 150});

  final double size;

  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  static const _confetti = [
    AppColors.accentSecondary,
    _paper,
    AppColors.blush,
    AppColors.accentSecondary,
    _paper,
    AppColors.blush,
    AppColors.accent,
    _paper,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dot = s * .55;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: s * 1.6,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            if (t >= 1) return const SizedBox.shrink();
            final pop = Curves.easeOutBack.transform(_seg(t, 0, .18));
            double sx = pop, sy = pop;
            if (t > .18 && t < .5) {
              final k = (t - .18) / .32;
              final w = math.sin(k * math.pi * 2) * (1 - k);
              sx = 1 + .25 * w;
              sy = 1 - .25 * w;
            }
            final fade = 1 - _seg(t, .72, 1);
            final heart = _seg(t, .2, .95);
            return Opacity(
              opacity: fade,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size.square(s * 1.6),
                    painter: _ConfettiPainter(t, s, _confetti),
                  ),
                  Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(sx, sy, 1),
                    child: MingleDot(size: dot, face: DotFace.love),
                  ),
                  Transform.translate(
                    offset: Offset(
                      0,
                      -dot * .55 - s * .3 * Curves.easeOut.transform(heart),
                    ),
                    child: Transform.scale(
                      scale: Curves.easeOutBack.transform(_seg(t, .2, .4)),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: s * .26,
                        color: _paper,
                        shadows: const [
                          Shadow(color: Color(0x55000000), blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.s, this.colors);
  final double t, s;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _seg(t, .15, .75, Curves.easeOutQuart);
    if (p <= 0 || p >= 1) return;
    final c = size.center(Offset.zero);
    for (var i = 0; i < colors.length; i++) {
      final a = i / colors.length * math.pi * 2;
      final d = s * (.5 + (i.isOdd ? .12 : 0)) * p;
      canvas.drawCircle(
        c + Offset(math.cos(a) * d, math.sin(a) * d),
        s * (i.isOdd ? .04 : .06) * (1 - p * .4),
        Paint()..color = colors[i].withValues(alpha: 1 - p),
      );
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// PIN
// ═══════════════════════════════════════════════════════════════════════════

/// Disegna Dot a forma di pin. Lo spazio di riferimento è 240×240 (come nel
/// brand kit): il corpo va da x 64→176, y 54→190 (punta).
/// Usato sia da [MinglePin] sia dai pin statici della mappa.
void paintDotPin(
  Canvas canvas, {
  required Color color,
  int? count,
  double blink = 1,
  double badgeScale = 1,
  Color faceColor = _ink,
  Color badgeColor = AppColors.accent,
  Color badgeTextColor = _paper,
}) {
  final body = Path()
    ..moveTo(120, 54)
    ..cubicTo(154, 54, 176, 78, 176, 108)
    ..cubicTo(176, 146, 120, 190, 120, 190)
    ..cubicTo(120, 190, 64, 146, 64, 108)
    ..cubicTo(64, 78, 86, 54, 120, 54)
    ..close();
  canvas.drawPath(
    body.shift(const Offset(0, 3)),
    Paint()
      ..color = Colors.black.withValues(alpha: .3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawPath(body, Paint()..color = color);
  canvas.drawPath(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .35),
  );
  final ink = Paint()..color = faceColor;
  for (final x in [108.0, 132.0]) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, 104), width: 10, height: 12 * blink),
      ink,
    );
  }
  canvas.drawPath(
    Path()
      ..moveTo(110, 124)
      ..quadraticBezierTo(120, 132, 130, 124),
    Paint()
      ..color = faceColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round,
  );
  if (count != null && count > 0 && badgeScale > 0) {
    canvas.save();
    canvas.translate(168, 64);
    canvas.scale(badgeScale);
    canvas.drawCircle(Offset.zero, 21, Paint()..color = AppColors.darkSurface);
    canvas.drawCircle(Offset.zero, 18, Paint()..color = badgeColor);
    final label = count > 99 ? '99+' : '$count';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: badgeTextColor,
          fontWeight: FontWeight.w800,
          fontSize: label.length > 2 ? 13 : 20,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

/// Dot-pin animato: spunta dal terreno con una molla, il badge conta i drop
/// e un'onda parte dalla base ogni ~2,8 s.
class MinglePin extends StatefulWidget {
  const MinglePin({
    super.key,
    this.size = 120,
    this.color = AppColors.accent,
    this.count,
  });

  final double size;
  final Color color;
  final int? count;

  @override
  State<MinglePin> createState() => _MinglePinState();
}

class _MinglePinState extends State<MinglePin>
    with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _pop.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pop, _idle]),
        builder: (_, _) => CustomPaint(
          painter: _PinPainter(
            pop: Curves.elasticOut.transform(_pop.value),
            badge: Curves.easeOutBack.transform(_seg(_pop.value, .3, .55)),
            idle: _idle.value,
            color: widget.color,
            count: widget.count,
          ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({
    required this.pop,
    required this.badge,
    required this.idle,
    required this.color,
    required this.count,
  });

  final double pop, badge, idle;
  final Color color;
  final int? count;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240);
    // Onda alla base
    final w = _seg(idle, .05, .5, Curves.easeOut);
    if (w > 0 && w < 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(120, 196),
          width: 60 * (.4 + 2 * w),
          height: 16 * (.4 + 2 * w),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: .7 * (1 - w)),
      );
    }
    // Pin che spunta (scala dalla punta)
    canvas.translate(120, 190);
    canvas.scale(pop.clamp(0.0, 1.3), pop.clamp(0.0, 1.3));
    canvas.translate(-120, -190);
    final ph = idle * 2800 % 4200;
    final blink = ph > 3930 && ph < 4030 ? .1 : 1.0;
    paintDotPin(
      canvas,
      color: color,
      count: count,
      blink: blink,
      badgeScale: badge,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PinPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// APP ICON
// ═══════════════════════════════════════════════════════════════════════════

/// L'icona dell'app animata: la "m" con Dot al posto del punto che salta.
class MingleAppIcon extends StatefulWidget {
  const MingleAppIcon({super.key, this.size = 96});

  final double size;

  @override
  State<MingleAppIcon> createState() => _MingleAppIconState();
}

class _MingleAppIconState extends State<MingleAppIcon>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _float.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dot = s * .2;
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _hop]),
      builder: (_, _) {
        final f = math.sin(_float.value * math.pi * 2);
        final h = _hop.value;
        // .55 squash → .72 salto → .84 atterraggio → .92 fermo
        double y = 0, sx = 1, sy = 1;
        if (h > .55 && h < .62) {
          final k = (h - .55) / .07;
          sx = 1 + .25 * k;
          sy = 1 - .25 * k;
        } else if (h >= .62 && h < .84) {
          final k = (h - .62) / .22;
          y = -math.sin(k * math.pi) * dot * 1.4;
          sx = .9;
          sy = 1.1;
        } else if (h >= .84 && h < .92) {
          final k = math.sin((h - .84) / .08 * math.pi);
          sx = 1 + .15 * k;
          sy = 1 - .15 * k;
        }
        return Transform.translate(
          offset: Offset(0, -f * s * .04),
          child: Transform.rotate(
            angle: -f * .05,
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(s * .29),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: .4),
                    blurRadius: s * .25,
                    offset: Offset(0, s * .08),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: s * .14),
                    child: Text(
                      'm',
                      style: GoogleFonts.oi(
                        fontSize: s * .44,
                        height: 1,
                        color: _paper,
                      ),
                    ),
                  ),
                  SizedBox(width: s * .01),
                  Padding(
                    padding: EdgeInsets.only(bottom: s * .22),
                    child: Transform.translate(
                      offset: Offset(0, y),
                      child: Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.diagonal3Values(sx, sy, 1),
                        child: MingleDot(
                          size: dot,
                          color: AppColors.accentSecondary,
                          showFace: dot >= 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARQUEE
// ═══════════════════════════════════════════════════════════════════════════

/// Nastro di testo Oi che scorre all'infinito, con un punto tra le parole.
class MingleMarquee extends StatefulWidget {
  const MingleMarquee({
    super.key,
    this.items = const [
      'lascia il segno',
      'mingle.',
      'la tua città, segreta',
      'mingle.',
      'trova il segno',
      'mingle.',
    ],
    this.background = AppColors.accent,
    this.foreground = _ink,
    this.fontSize = 28,
    this.speed = 50,
    this.reverse = false,
  });

  final List<String> items;
  final Color background;
  final Color foreground;
  final double fontSize;

  /// Pixel al secondo.
  final double speed;
  final bool reverse;

  @override
  State<MingleMarquee> createState() => _MingleMarqueeState();
}

class _MingleMarqueeState extends State<MingleMarquee>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.fontSize;
    final style = GoogleFonts.oi(
      fontSize: fs,
      height: 1.15,
      color: widget.foreground,
    );
    final gap = fs * .6;
    final dot = fs * .42;
    var segment = 0.0;
    for (final it in widget.items) {
      final tp = TextPainter(
        text: TextSpan(text: it, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      segment += tp.width + gap + dot + gap;
    }
    final still = _reduceMotion(context);

    Widget strip() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final it in widget.items) ...[
          Text(it, style: style),
          SizedBox(width: gap),
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: widget.foreground,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: gap),
        ],
      ],
    );

    return ExcludeSemantics(
      child: Container(
        color: widget.background,
        padding: EdgeInsets.symmetric(vertical: fs * .35),
        child: LayoutBuilder(
          builder: (context, box) {
            final copies = (box.maxWidth / segment).ceil() + 1;
            return ClipRect(
              child: SizedBox(
                height: fs * 1.15,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _t,
                    builder: (_, t, child) {
                      var shift = still ? 0.0 : (t * widget.speed) % segment;
                      if (widget.reverse) shift = segment - shift;
                      return Transform.translate(
                        offset: Offset(-shift, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (var i = 0; i <= copies; i++) strip()],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
