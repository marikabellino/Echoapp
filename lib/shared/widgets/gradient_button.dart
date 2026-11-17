import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_motion.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// Big pill CTA del brand mingle.: magenta pieno (niente sfumature, come nel
/// brand kit) che si schiaccia al tocco e torna su con una molla.
///
/// [gradient] è tenuto solo per compatibilità: il brand non usa più
/// sfumature, quindi il pulsante è sempre magenta pieno.
class GradientButton extends StatefulWidget {
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
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onPressed != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    const bg = AppColors.accent;
    const fg = Colors.white;

    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: _down ? AppMotion.tap : AppMotion.pop,
        curve: _down ? AppMotion.tapCurve : AppMotion.popCurve,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: enabled ? bg : bg.withValues(alpha: 0.4),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: fg,
              disabledForegroundColor: fg.withValues(alpha: 0.6),
              shadowColor: Colors.transparent,
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
