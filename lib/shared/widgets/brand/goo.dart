import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Effetto metaball "goo": sfoca il figlio e poi alza il contrasto
/// dell'alpha, così forme vicine si fondono come gocce d'acqua.
/// È l'effetto "mingle" del brand.
class Goo extends StatelessWidget {
  const Goo({super.key, required this.child, this.blur = 8});

  final Widget child;
  final double blur;

  static const _threshold = ColorFilter.matrix([
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 24, -2550,
  ]);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColorFiltered(
        colorFilter: _threshold,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: child,
        ),
      ),
    );
  }
}
