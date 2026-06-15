import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
   static TextStyle displayLarge(BuildContext context) => GoogleFonts.libreBaskerville(
        fontSize: 42,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.1,
        letterSpacing: -0.5,
      );

  static TextStyle headline(BuildContext context) => GoogleFonts.roboto(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: -0.2,
      );

  static TextStyle body(BuildContext context) => GoogleFonts.roboto(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle bodySecondary(BuildContext context) => GoogleFonts.roboto(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}