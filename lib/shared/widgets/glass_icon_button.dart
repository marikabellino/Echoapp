import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Circular frosted-glass icon button — iOS 17+ "Liquid Glass" puck.
/// Neutral grey/translucent regardless of theme accent color.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 50,
    this.iconSize = 25,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Platform.isIOS || Platform.isMacOS;
    final blurSigma = isIOS ? 30.0 : 20.0;

    final bg = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.55);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.08);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black.withValues(alpha: 0.75);

    // The "ios" back-chevron glyphs aren't visually centered in their own
    // bounding box (extra padding on the right) — nudge them to compensate.
    final isBackArrow = icon == Icons.arrow_back_ios_new_rounded ||
        icon == Icons.arrow_back_ios_rounded ||
        icon == Icons.arrow_back_ios_new ||
        icon == Icons.arrow_back_ios;

    Widget button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: Border.all(color: border, width: isIOS ? 0.5 : 1.0),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: Padding(
                  padding: isBackArrow
                      ? const EdgeInsets.only(left: 2)
                      : EdgeInsets.zero,
                  child: Icon(icon, size: iconSize, color: iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
