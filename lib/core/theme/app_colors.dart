import 'package:flutter/material.dart';

class AppColors {
  static const darkBackground = Color(0xFF0D0B0E);
  static const darkSurface = Color(0xFF17131A);
  static const darkSurfaceLight = Color(0xFF221C26);
  static const darkSurfaceHigh = Color(0xFF2C2531);

  static const lightBackground = Color(0xFFFAF7F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSoft = Color(0xFFF1ECE9);

  static const primary = Color(0xFFFFFFFF);

  static const accent = Color(0xFFFF3D7F);

  static const accentSecondary = Color(0xFFFFB547);

  static const accentSecondaryOnLight = Color(0xFFB36B00);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentSecondary],
  );

  static const textDark = Color(0xFF17121A);
  static const textLight = Color(0xFFF7F1F4);
  static const textSecondaryDark = Color(0xFF6E6470);
  static const textSecondaryLight = Color(0xFFA79CA8);

  static const borderDark = Color(0x14FFFFFF);
  static const borderLight = Color(0x14000000);
  static const glow = Color(0x66FF3D7F);

  static const moodDrop = accent;
  static const moodLove = Color(0xFFFF6B8B);
  static const moodSecret = Color(0xFFA78BFA);
  static const moodDream = Color(0xFFFFC857);
  static const moodLost = Color(0xFF34D3BC);
  static const moodFood = Color(0xFFFF8A3D);

  // ─── Alias del brand kit ──────────────────────────────────────────────────
  /// Inchiostro: lo sfondo di mingle.
  static const ink = darkBackground;

  /// Carta: il bianco caldo del wordmark.
  static const paper = textLight;

  /// Rosa chiaro: guance di Dot, lingua, dettagli. Non è un colore "di senso".
  static const blush = Color(0xFFFF8FB1);

  // ─── Colori di stato (niente verde/rosso iOS) ─────────────────────────────
  static const success = Color(0xFF34D3BC);
  static const error = Color(0xFFFF5A5A);
  static const info = paper;
}
