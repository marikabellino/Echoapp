import 'dart:ui';

import 'package:flutter/material.dart';

/// A [SliverPersistentHeaderDelegate] that keeps a fixed-size [pinned] widget
/// (e.g. a page title) always visible, while everything in [dissolving]
/// fades away as the user scrolls. A frosted-glass scrim fades in behind it,
/// with both blur and tint softened toward the bottom edge (via [ShaderMask])
/// so there is never a hard seam where it meets the scrolling content below.
class CollapsingGlassHeaderDelegate extends SliverPersistentHeaderDelegate {
  const CollapsingGlassHeaderDelegate({
    required this.isDark,
    required this.minExtent,
    required this.maxExtent,
    required this.pinned,
    required this.dissolving,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 0),
    this.pinnedGap = 6,
  });

  final bool isDark;
  @override
  final double minExtent;
  @override
  final double maxExtent;

  /// Always visible, fixed size/style — never fades or resizes.
  final WidgetBuilder pinned;

  /// Fades out as the user scrolls past [minExtent].
  final WidgetBuilder dissolving;

  final EdgeInsets padding;
  final double pinnedGap;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final tint = isDark ? Colors.black : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Glass scrim: both blur and tint fade out toward the bottom, so
        // there's no hard edge where it meets the scrolling content.
        if (t > 0)
          Positioned.fill(
            child: Opacity(
              opacity: t,
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.black, Colors.transparent],
                    stops: [0.0, 0.45, 1.0],
                  ).createShader(rect),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Pinned content on top, fixed size/font, always visible.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pinned(context),
                SizedBox(height: pinnedGap),
                Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: dissolving(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // pinned/dissolving are fresh closures each build (they capture live state
  // like tab index or search text), so identity comparison can't tell if
  // their content changed — always rebuild, the cost is negligible for a
  // header.
  @override
  bool shouldRebuild(covariant CollapsingGlassHeaderDelegate oldDelegate) => true;
}
