import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  /// Bold, playful wordmark style — used only for the app logo/name.
  static TextStyle logo(BuildContext context) => GoogleFonts.oi(
    fontSize: 42,
    fontWeight: FontWeight.normal,
    color: Theme.of(context).colorScheme.onSurface,
    height: 1.1,
    letterSpacing: -0.5,
  );

  /// Titoli grandi: Bricolage Grotesque, pesante e stretto, come nel
  /// brand kit.
  static TextStyle displayLarge(BuildContext context) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.0,
        letterSpacing: -1.2,
      );

  static TextStyle headline(BuildContext context) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: -0.4,
      );

  /// Etichette maiuscole tecniche (DM Mono), es. "LA TUA CERCHIA".
  static TextStyle eyebrow(BuildContext context) => GoogleFonts.dmMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.6,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle body(BuildContext context) => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle bodySecondary(BuildContext context) => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}
