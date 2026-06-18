import 'dart:io';
import 'dart:ui';

import 'package:apptest/core/theme/app_colors.dart';
import 'package:apptest/core/theme/app_radius.dart';
import 'package:apptest/features/messaging/providers/messaging_provider.dart';
import 'package:apptest/features/notifications/providers/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FloatingNavbar extends ConsumerWidget {
  final int currentIndex;
  final Function(int) onTap;

  const FloatingNavbar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadCountProvider);
    final unreadNotifs = ref.watch(unreadNotificationCountProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = Platform.isIOS || Platform.isMacOS;

    final Color bgColor;
    final Color borderColor;
    final double blurSigma;
    final double borderWidth;

    if (isIOS) {
      blurSigma = 32;
      borderWidth = 0.5;
      bgColor = isDark
          ? Colors.black.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.72);
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.90);
    } else {
      blurSigma = 20;
      borderWidth = 1.0;
      bgColor = isDark
          ? Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.82)
          : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92);
      borderColor = isDark
          ? Theme.of(context).dividerColor
          : Theme.of(context).colorScheme.outlineVariant;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            height: 71,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: [
                if (isIOS && isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: LucideIcons.compass,
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  icon: LucideIcons.map,
                  selected: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
                _NavItem(
                  icon: LucideIcons.plus,
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
                _NavItem(
                  icon: LucideIcons.messageCircle,
                  selected: currentIndex == 3,
                  onTap: () => onTap(3),
                  badge: unread,
                ),
                _NavItem(
                  icon: LucideIcons.user,
                  selected: currentIndex == 4,
                  onTap: () => onTap(4),
                  badge: unreadNotifs,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? (selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4))
        : (selected ? AppColors.accent : AppColors.accent.withValues(alpha: 0.35));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          if (badge > 0)
            Positioned(
              top: 6,
              right: 6,
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
  }
}
