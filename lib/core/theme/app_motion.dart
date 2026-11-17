import 'package:flutter/animation.dart';

/// Le cinque curve di mingle. Tutta l'app si muove con queste:
/// se un'animazione non ci rientra, probabilmente non serve.
abstract class AppMotion {
  /// Pulsanti, toggle.
  static const tap = Duration(milliseconds: 120);
  static const tapCurve = Curves.easeOut;

  /// Chip, badge, sheet.
  static const pop = Duration(milliseconds: 280);
  static const popCurve = Curves.easeOutBack;

  /// Fusioni, transizioni di pagina.
  static const mingle = Duration(milliseconds: 600);
  static const mingleCurve = Curves.easeInOutCubic;

  /// Pubblicazione, atterraggi.
  static const drop = Duration(milliseconds: 900);
  static const dropCurve = Curves.bounceOut;

  /// Dot, like, pin.
  static const elastic = Duration(milliseconds: 1100);
  static const elasticCurve = Curves.elasticOut;
}
