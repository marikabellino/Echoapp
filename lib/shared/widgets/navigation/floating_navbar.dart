import 'dart:io';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FloatingNavbar extends ConsumerStatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback? onSwipedLeft;
  final VoidCallback? onSwipedRight;

  const FloatingNavbar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onSwipedLeft,
    this.onSwipedRight,
  });

  @override
  ConsumerState<FloatingNavbar> createState() => _FloatingNavbarState();
}

class _FloatingNavbarState extends ConsumerState<FloatingNavbar>
    with SingleTickerProviderStateMixin {
  // Unbounded controller — value represents the floating index (0.0 … 4.0).
  late final AnimationController _pill;
  double? _dragStartX;
  double _dragStartValue = 0;
  double _navbarWidth = 0;

  @override
  void initState() {
    super.initState();
    _pill = AnimationController.unbounded(
      value: widget.currentIndex.toDouble(),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(FloatingNavbar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex && _dragStartX == null) {
      _pill.animateTo(
        widget.currentIndex.toDouble(),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutExpo,
      );
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails d) {
    _pill.stop();
    _dragStartX = d.localPosition.dx;
    _dragStartValue = _pill.value;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dragStartX == null || _navbarWidth == 0) return;
    final itemW = _navbarWidth / 5;
    final delta = d.localPosition.dx - _dragStartX!;
    _pill.value = (_dragStartValue + delta / itemW).clamp(0.0, 4.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragStartX == null) return;
    _dragStartX = null;

    // Project 150 ms ahead with current velocity, then round to nearest tab.
    final itemW = _navbarWidth / 5;
    final velocityContrib = (d.primaryVelocity ?? 0) / itemW * 0.15;
    final projected = (_pill.value + velocityContrib).clamp(0.0, 4.0);
    final target = projected.round().clamp(0, 4);

    if (target != widget.currentIndex) widget.onTap(target);

    _pill.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 310),
      curve: Curves.easeOutExpo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(totalUnreadCountProvider);
    final unreadNotifs = ref.watch(unreadNotificationCountProvider);
    final scrollOffset = ref.watch(scrollOffsetProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Platform.isIOS || Platform.isMacOS;

    final t = (scrollOffset / 200.0).clamp(0.0, 1.0);
    final height = 68.0 - (t * 12.0);
    final lateralPadding = 20.0 + (t * 18.0);
    final iconScale = 1.0 - (t * 0.12);

    final double blurSigma = isIOS ? 36.0 : 22.0;
    final Color bgColor = isDark
        ? Colors.black.withValues(alpha: 0.50)
        : Colors.white.withValues(alpha: 0.68);

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          left: lateralPadding,
          right: lateralPadding,
          bottom: bottomInset + 10,
        ),
        child: ClipRRect(
          clipBehavior: Clip.antiAliasWithSaveLayer,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: height,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _navbarWidth = constraints.maxWidth;
                  return _NavbarContent(
                    currentIndex: widget.currentIndex,
                    onTap: widget.onTap,
                    unread: unread,
                    unreadNotifs: unreadNotifs,
                    iconScale: iconScale,
                    pill: _pill,
                    totalWidth: constraints.maxWidth,
                    isIOS: isIOS,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NavbarContent extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int unread;
  final int unreadNotifs;
  final double iconScale;
  final AnimationController pill;
  final double totalWidth;
  final bool isIOS;

  const _NavbarContent({
    required this.currentIndex,
    required this.onTap,
    required this.unread,
    required this.unreadNotifs,
    required this.iconScale,
    required this.pill,
    required this.totalWidth,
    required this.isIOS,
  });

  @override
  Widget build(BuildContext context) {
    const hPad = 5.0;
    final itemW = totalWidth / 5;

    return Stack(
      children: [
        // Sliding liquid-glass pill — rendered behind icons.
        AnimatedBuilder(
          animation: pill,
          builder: (_, _) {
            return Positioned(
              left: pill.value * itemW + hPad,
              top: 6,
              bottom: 6,
              width: itemW - hPad * 2,
              child: const _LiquidGlassPill(radius: 26.0),
            );
          },
        ),

        // Icon row — each icon reads pill.value for colour/scale.
        Row(
          children: [
            Expanded(
              child: _NavIcon(
                index: 0,
                icon: isIOS ? CupertinoIcons.compass : LucideIcons.compass,
                onTap: () => onTap(0),
                iconScale: iconScale,
                pill: pill,
              ),
            ),
            Expanded(
              child: _NavIcon(
                index: 1,
                icon: isIOS ? CupertinoIcons.map : LucideIcons.map,
                onTap: () => onTap(1),
                iconScale: iconScale,
                pill: pill,
              ),
            ),
            Expanded(
              child: _NavIcon(
                index: 2,
                icon: isIOS ? CupertinoIcons.plus_circle : LucideIcons.plus,
                onTap: () => onTap(2),
                iconScale: iconScale,
                pill: pill,
              ),
            ),
            Expanded(
              child: _NavIcon(
                index: 3,
                icon: isIOS ? CupertinoIcons.chat_bubble : LucideIcons.messageCircle,
                onTap: () => onTap(3),
                iconScale: iconScale,
                pill: pill,
                badge: unread,
              ),
            ),
            Expanded(
              child: _NavIcon(
                index: 4,
                icon: isIOS ? CupertinoIcons.person : LucideIcons.user,
                onTap: () => onTap(4),
                iconScale: iconScale,
                pill: pill,
                badge: unreadNotifs,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LiquidGlassPill extends StatelessWidget {
  final double radius;

  const _LiquidGlassPill({required this.radius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        // Extra blur makes this region feel like a thicker glass slab.
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // Top-to-bottom gradient gives the glass depth.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.07),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      Colors.white.withValues(alpha: 0.65),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.90),
              width: 0.7,
            ),
            boxShadow: [
              // Drop shadow for lift.
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
              // Inner top-edge highlight.
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.55),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NavIcon extends StatelessWidget {
  final int index;
  final IconData icon;
  final VoidCallback onTap;
  final double iconScale;
  final AnimationController pill;
  final int badge;

  const _NavIcon({
    required this.index,
    required this.icon,
    required this.onTap,
    required this.iconScale,
    required this.pill,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = isDark ? Colors.white : AppColors.accent;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.32)
        : Colors.black.withValues(alpha: 0.38);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: pill,
        builder: (context, _) {
          // 0 → inactive, 1 → fully active (pill centred on this icon).
          final t = (1.0 - (pill.value - index).abs()).clamp(0.0, 1.0);
          final color = Color.lerp(inactiveColor, activeColor, t)!;
          final scale = lerpDouble(0.86, 1.0, t) * iconScale;

          return ConstrainedBox(
            constraints: const BoxConstraints.expand(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Icon(icon, size: 22.0, color: color),
                ),
                if (badge > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 15, minHeight: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;
