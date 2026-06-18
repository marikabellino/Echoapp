import 'package:apptest/core/theme/app_colors.dart';
import 'package:apptest/core/theme/app_text_styles.dart';
import 'package:apptest/features/notifications/domain/models/notification_model.dart';
import 'package:apptest/features/notifications/providers/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsSheet extends ConsumerWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mark all as read when sheet opens
    ref.read(notificationsProvider.notifier).markAllRead();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181528) : const Color(0xFFF3F1FC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(
              children: [
                Text('Notifiche', style: AppTextStyles.headline(context)),
                const Spacer(),
                if (notifications.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        ref.read(notificationsProvider.notifier).clear(),
                    child: Text(
                      'Cancella tutto',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.accent.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Expanded(
            child: notifications.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, thickness: 0.4, indent: 64),
                    itemBuilder: (_, i) =>
                        _NotificationTile(notification: notifications[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (icon, iconColor) = switch (notification.type) {
      NotificationType.like => (LucideIcons.heart, const Color(0xFFE8879C)),
      NotificationType.connectionRequest =>
        (LucideIcons.userPlus, AppColors.accent),
      NotificationType.proximity =>
        (LucideIcons.mapPin, const Color(0xFF5BC4B0)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.body,
                  style: AppTextStyles.bodySecondary(context).copyWith(
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeago.format(notification.createdAt, locale: 'it'),
                  style: AppTextStyles.bodySecondary(context).copyWith(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.bell,
            size: 40,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 14),
          Text(
            'Nessuna notifica ancora',
            style: AppTextStyles.bodySecondary(context),
          ),
        ],
      ),
    );
  }
}
