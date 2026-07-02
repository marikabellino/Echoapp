import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS-style bottom sheet surface.
///
/// Use [height] for fixed-height sheets (e.g. lists, tabs).
/// Use [maxHeight] for sheets that grow with their content up to a limit.
/// Leave both null to min-wrap content (e.g. action/form sheets).
class EchoBottomSheet extends StatelessWidget {
  const EchoBottomSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.height,
    this.maxHeight,
  }) : assert(
          height == null || maxHeight == null,
          'Use either height or maxHeight, not both.',
        );

  final Widget child;
  final bool showHandle;
  final double? height;
  final double? maxHeight;

  static const _radius = Radius.circular(12);
  static const _borderRadius = BorderRadius.vertical(top: _radius);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.97);

    final handle = Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(2.5),
      ),
    );

    final hasFixedHeight = height != null;

    final content = Column(
      mainAxisSize: hasFixedHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHandle) ...[
          const SizedBox(height: 8),
          Center(child: handle),
          const SizedBox(height: 4),
        ],
        if (hasFixedHeight) Expanded(child: child) else child,
      ],
    );

    BoxConstraints? constraints;
    if (maxHeight != null) {
      constraints = BoxConstraints(maxHeight: maxHeight!);
    }

    return ClipRRect(
      borderRadius: _borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          height: height,
          constraints: constraints,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: _borderRadius,
          ),
          child: content,
        ),
      ),
    );
  }
}
