import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// Big pill CTA con sfumatura blu → arancio.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.gradient = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        gradient: enabled && gradient
            ? const LinearGradient(
                colors: [AppColors.accent, AppColors.accentSecondary],
              )
            : null,
        color: !enabled
            ? AppColors.accent.withValues(alpha: 0.4)
            : (gradient ? null : AppColors.accent),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      ),
    );
  }
}
