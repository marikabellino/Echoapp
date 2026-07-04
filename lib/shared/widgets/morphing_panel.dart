import 'dart:ui';

import 'package:flutter/material.dart';

/// Opens a panel that morphs out of the tapped widget's own position — the
/// button itself grows into a full glass panel, instead of sliding up from
/// an edge like a sheet or popping up centered like a dialog.
///
/// [context] must belong to the widget that should act as the origin (e.g.
/// wrap the tappable icon in a [Builder] to get a context scoped to just
/// that icon, not the whole card it lives in).
Future<T?> showMorphingPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final box = context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero) & box.size;

  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => _MorphingPanel(
        animation: animation,
        origin: origin,
        builder: builder,
      ),
    ),
  );
}

class _MorphingPanel extends StatelessWidget {
  const _MorphingPanel({
    required this.animation,
    required this.origin,
    required this.builder,
  });

  final Animation<double> animation;
  final Rect origin;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    // Cap the panel at ~half the screen height (instead of nearly full
    // screen) and center it vertically, so with little/no content it reads
    // as a modest centered card, not an oversized mostly-empty sheet.
    final targetHeight = screen.height * 0.42 - keyboardInset * 0.5;
    final target = Rect.fromLTWH(
      20,
      (screen.height - targetHeight) / 2 - keyboardInset * 0.5,
      screen.width - 40,
      targetHeight,
    );

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      // Built once and reused every frame — building CommentsSheet fresh on
      // each tick was recreating its layout mid-animation and caused a
      // RenderFlex overflow, plus TextField needs a Material ancestor.
      child: Material(
        type: MaterialType.transparency,
        child: Builder(builder: builder),
      ),
      builder: (context, child) {
        final t = curved.value.clamp(0.0, 1.0);
        final rect = Rect.lerp(origin, target, t)!;
        final radius = lerpDouble(origin.shortestSide / 2, 28, t)!;
        // content only starts fading in once the shape is mostly grown —
        // crammed content in a tiny circle would just look broken.
        final contentOpacity = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
        final scrimOpacity = 0.35 * t;
        final blurSigma = 22 * t;

        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Container(
                  color: Colors.black.withValues(alpha: scrimOpacity),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.75,
                      ),
                    ),
                    // The content is always laid out at its final target
                    // size (never squeezed into the growing rect), and just
                    // gets progressively revealed as the ClipRRect above
                    // grows — this avoids ever overflowing mid-animation.
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: target.width,
                      maxWidth: target.width,
                      minHeight: target.height,
                      maxHeight: target.height,
                      child: SizedBox(
                        width: target.width,
                        height: target.height,
                        child: Opacity(opacity: contentOpacity, child: child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
