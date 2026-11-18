import 'package:echo/features/drop/presentation/widgets/relation_badge.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/drop_image_signer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class DropGridTile extends StatefulWidget {
  const DropGridTile({
    required this.drop,
    required this.onTap,
    required this.onLongPress,
  });

  final DropModel drop;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<DropGridTile> createState() => _DropGridTileState();
}

class _DropGridTileState extends State<DropGridTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final drop = widget.drop;
    final hasImage = drop.imageUrl != null;
    final isPrivate = drop.visibility != DropVisibility.public;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: () {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: dropHeroTag(drop),
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: drop.imageUrl!,
                        cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        placeholder: (_, _) =>
                            const ColoredBox(color: AppColors.darkSurfaceLight),
                        errorWidget: (_, _, _) => const DropPlaceholder(),
                      )
                    : const DropPlaceholder(iconSize: 28),
              ),
              if (drop.eventTitle != null)
                const Positioned(
                  top: 6,
                  left: 6,
                  child: _TileBadge(
                    icon: Icons.event_rounded,
                    color: AppColors.accentSecondary,
                  ),
                ),
              if (isPrivate)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _TileBadge(
                    icon: drop.visibility.icon,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}

class ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  ProfileTabsDelegate({
    this.leading,
    required this.topInset,
    required this.index,
    required this.onTap,
    required this.labels,
  });

  final double topInset;

  final Widget? leading;
  final int index;
  final ValueChanged<int> onTap;
  final List<String> labels;

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.map_outlined,
    Icons.alternate_email_rounded,
  ];
  static const _height = 56.0;

  @override
  double get minExtent => _height + topInset;
  @override
  double get maxExtent => _height + topInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final pinned = overlapsContent || shrinkOffset > 0;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final count = labels.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: pinned
          ? Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96)
          : Colors.transparent,
      padding: EdgeInsets.fromLTRB(16, topInset + 4, 16, 8),
      child: Row(
        children: [
          if (pinned && leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SlideToSelect(
              count: count,
              index: index,
              onChanged: (i) {
                HapticFeedback.selectionClick();
                onTap(i);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(
                        count > 1 ? 2 * index / (count - 1) - 1 : 0,
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / count,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (i != index)
                                    HapticFeedback.selectionClick();
                                  onTap(i);
                                },
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _icons[i % _icons.length],
                                        size: 16,
                                        color: i == index
                                            ? Colors.white
                                            : muted,
                                      ),
                                      const SizedBox(width: 6),
                                      AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: i == index
                                              ? Colors.white
                                              : muted,
                                        ),
                                        child: Text(labels[i]),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(ProfileTabsDelegate old) =>
      old.index != index ||
      (old.leading == null) != (leading == null) ||
      old.topInset != topInset ||
      old.labels.join() != labels.join();
}

class ProfileDropsMap extends StatefulWidget {
  const ProfileDropsMap({required this.drops, required this.onDropTap});

  final List<DropModel> drops;
  final void Function(DropModel) onDropTap;

  @override
  State<ProfileDropsMap> createState() => _ProfileDropsMapState();
}

class _ProfileDropsMapState extends State<ProfileDropsMap> {
  MapLibreMapController? _controller;

  int get _placesCount => widget.drops
      .map(
        (d) =>
            '${d.latitude.toStringAsFixed(3)},${d.longitude.toStringAsFixed(3)}',
      )
      .toSet()
      .length;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  void _onCircleTapped(Circle circle) {
    final id = circle.data?['id'];
    final drop = widget.drops.where((d) => d.id == id).firstOrNull;
    if (drop != null) widget.onDropTap(drop);
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || widget.drops.isEmpty) return;
    await c.clearCircles();
    await c.addCircles(
      [
        for (final d in widget.drops)
          CircleOptions(
            geometry: LatLng(d.latitude, d.longitude),
            circleRadius: 8,
            circleColor: _hex(AppColors.accent),
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
      ],
      [
        for (final d in widget.drops) {'id': d.id},
      ],
    );
    _fitToDrops();
  }

  void _fitToDrops() {
    final c = _controller;
    final drops = widget.drops;
    if (c == null || drops.isEmpty) return;
    if (drops.length == 1) {
      c.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(drops.first.latitude, drops.first.longitude),
          14,
        ),
      );
      return;
    }
    var minLat = drops.first.latitude, maxLat = minLat;
    var minLng = drops.first.longitude, maxLng = minLng;
    for (final d in drops) {
      if (d.latitude < minLat) minLat = d.latitude;
      if (d.latitude > maxLat) maxLat = d.latitude;
      if (d.longitude < minLng) minLng = d.longitude;
      if (d.longitude > maxLng) maxLng = d.longitude;
    }
    c.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 48,
        top: 48,
        right: 48,
        bottom: 48,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.onCircleTapped.remove(_onCircleTapped);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drops = widget.drops;
    if (drops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(36),
        child: Text(
          'La tua mappa è ancora vuota.\nOgni drop che lasci diventa un punto qui.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySecondary(context),
        ),
      );
    }
    final first = drops.first;
    final places = _placesCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            '${drops.length} drop in $places ${places == 1 ? 'posto' : 'posti'}',
            style: AppTextStyles.bodySecondary(context),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: MapLibreMap(
              styleString: AppConstants.maptilerDarkStyle,
              initialCameraPosition: CameraPosition(
                target: LatLng(first.latitude, first.longitude),
                zoom: 12,
              ),
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              onMapCreated: (c) {
                _controller = c;
                c.onCircleTapped.add(_onCircleTapped);
              },
              onStyleLoadedCallback: _onStyleLoaded,
              compassEnabled: false,
              myLocationEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileCover extends StatelessWidget {
  const ProfileCover({
    required this.imageUrl,
    required this.topInset,
    required this.child,
  });

  final String? imageUrl;
  final double topInset;
  final Widget child;

  static const _saturate = <double>[
    1.6262, -0.5720, -0.0542, 0, 0, //
    -0.1738, 1.2280, -0.0542, 0, 0, //
    -0.1738, -0.5720, 1.7458, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.6, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            child: imageUrl == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                    ),
                  )
                : ClipRect(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix(_saturate),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl!,
                          cacheKey: DropImageSigner.cacheKey(imageUrl!),
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          fadeInDuration: const Duration(milliseconds: 600),
                          errorWidget: (_, _, _) => const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.55, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.30),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: child,
        ),
      ],
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );
  }
}

class GlassButton extends StatefulWidget {
  const GlassButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: Colors.white.withValues(alpha: _pressed ? 0.16 : 0.10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: enabled ? 1 : 0.5),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class StatItem extends StatelessWidget {
  const StatItem({
    required this.value,
    required this.label,
    this.badge = 0,
    this.onTap,
  });

  final int value;
  final String label;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}',
                  style: AppTextStyles.headline(context).copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -14,
                  top: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySecondary(
              context,
            ).copyWith(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class StatDivider extends StatelessWidget {
  const StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.white.withValues(alpha: 0.14),
    );
  }
}

class SlideToSelect extends StatelessWidget {
  const SlideToSelect({
    required this.count,
    required this.index,
    required this.onChanged,
    required this.child,
  });

  final int count;
  final int index;
  final ValueChanged<int> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(double dx) {
          final i = (dx / constraints.maxWidth * count).floor().clamp(
            0,
            count - 1,
          );
          if (i != index) onChanged(i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          child: child,
        );
      },
    );
  }
}
