import 'dart:math';

import 'package:echo/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;

  const AnimatedGradientBackground({super.key, required this.child});
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
              colors: isDark
                  ? [const Color(0xFF132420), AppColors.darkBackground]
                  : [const Color(0xFFDCF3EE), AppColors.lightBackground],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
