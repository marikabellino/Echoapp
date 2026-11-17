import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:pull_down_button/pull_down_button.dart';

class AppTheme {
  static const _pullDownMenuTheme = PullDownButtonTheme(
    routeTheme: PullDownMenuRouteTheme(width: 190),
    dividerTheme: PullDownMenuDividerTheme(dividerColor: Colors.transparent),
  );

  static final _elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );

  static final _outlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );

  static final _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.accent,
      shape: const StadiumBorder(),
    ),
  );

  static InputDecorationTheme _inputTheme(ColorScheme colorScheme) {
    final radius = BorderRadius.circular(AppRadius.md);
    final none = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    return InputDecorationTheme(
      filled: false,
      border: none,
      enabledBorder: none,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: TextStyle(
        color: colorScheme.onSurface.withValues(alpha: 0.38),
      ),
    );
  }

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      // Material 3 predictive-back / zoom transition on Android
      TargetPlatform.android: ZoomPageTransitionsBuilder(
        allowEnterRouteSnapshotting: false,
      ),
      // iOS keeps its default slide/hero transition
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF4A1328),
      onPrimaryContainer: Color(0xFFFFD9E4),
      secondary: AppColors.accentSecondary,
      onSecondary: Color(0xFF2B1A00),
      secondaryContainer: Color(0xFF3D2A0A),
      onSecondaryContainer: Color(0xFFFFE2B8),
      tertiary: AppColors.moodSecret,
      onTertiary: Color(0xFF1E1340),
      error: Color(0xFFFF5A5A),
      onError: Colors.white,
      errorContainer: Color(0xFF4A1414),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkBackground,
      onSurface: AppColors.textLight,
      onSurfaceVariant: AppColors.textSecondaryLight,
      surfaceContainerLowest: Color(0xFF0A080B),
      surfaceContainerLow: Color(0xFF131016),
      surfaceContainer: AppColors.darkSurface,
      surfaceContainerHigh: AppColors.darkSurfaceLight,
      surfaceContainerHighest: AppColors.darkSurfaceHigh,
      outline: Color(0xFF4A414D),
      outlineVariant: Color(0xFF2E2731),
      inverseSurface: AppColors.textLight,
      onInverseSurface: AppColors.darkBackground,
      inversePrimary: Color(0xFFB0124F),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: colorScheme,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      dividerColor: AppColors.borderDark,
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.borderDark),
        ),
      ),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _inputTheme(colorScheme),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      extensions: const [_pullDownMenuTheme],
    );
  }

  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: AppColors.accent,
          surface: AppColors.lightBackground,
          surfaceTint: Colors.transparent,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: colorScheme,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      dividerColor: AppColors.borderLight,
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _inputTheme(colorScheme),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      extensions: const [_pullDownMenuTheme],
    );
  }
}
