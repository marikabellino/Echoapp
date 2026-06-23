import 'dart:io';
import 'dart:ui';

import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;

  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Platform.isIOS || Platform.isMacOS;

    // iOS: stronger blur, more translucent — proper frosted glass feel
    // Android: tonal surface with subtle blur
    final blurSigma = isIOS ? 30.0 : 20.0;
    final Color bg;
    final Color border;

    if (isIOS) {
      bg = isDark
          ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.68);
      border = isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.75);
    } else {
      bg = isDark
          ? Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.80)
          : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92);
      border = isDark
          ? Theme.of(context).dividerColor
          : Theme.of(context).colorScheme.outlineVariant;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: border, width: isIOS ? 0.5 : 1.0),
            boxShadow: [
              if (isIOS && isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              if (isIOS && !isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              if (!isIOS && !isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
