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

   static TextStyle displayLarge(BuildContext context) => GoogleFonts.nunito(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.1,
        letterSpacing: -0.5,
      );

  static TextStyle headline(BuildContext context) => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: -0.2,
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