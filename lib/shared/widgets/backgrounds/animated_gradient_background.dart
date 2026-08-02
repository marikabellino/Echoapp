import 'dart:math';

import 'package:echo/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;

  /// Overrides the default tint colors of the radial gradient.
  /// First color is the center tint, second is the outer edge.
  final List<Color>? tintColors;

  const AnimatedGradientBackground({
    super.key,
    required this.child,
    this.tintColors,
  });
  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final value = controller.value;

        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                sin(value * pi * 2) * 0.3,
                cos(value * pi * 2) * 0.3,
              ),
              radius: 1.3,
              colors: widget.tintColors ??
                  (isDark
                      ? [AppColors.darkSurface, AppColors.darkBackground]
                      : [const Color(0xFFFAE0F0), AppColors.lightBackground]),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
