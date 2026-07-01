import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsSheet extends ConsumerStatefulWidget {
  const NotificationsSheet({super.key});

  @override
  ConsumerState<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    // Segna tutto come letto dopo il primo frame, fuori dalla fase di build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationsProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                GlassIconButton(
                  icon: Icons.close,
                  size: 32,
                  iconSize: 16,
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

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (icon, iconColor) = switch (notification.type) {
      NotificationType.like => (LucideIcons.heart, const Color(0xFFE8879C)),
      NotificationType.connectionRequest =>
        (LucideIcons.userPlus, AppColors.accent),
      NotificationType.proximity =>
        (LucideIcons.mapPin, const Color(0xFF5BC4B0)),
      NotificationType.message =>
        (LucideIcons.messageCircle, const Color(0xFF7B9CFF)),
    };

    Future<void> onTap() async {
      final fromId = notification.fromUserId;
      if (fromId == null) return;

      if (notification.type == NotificationType.message) {
        final convId = notification.conversationId;
        if (convId == null) return;
        final fromName = notification.fromUsername ?? '';
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              conversation: ConversationModel(
                id: convId,
                otherUserId: fromId,
                otherUsername: fromName,
                otherDisplayName: fromName,
              ),
            ),
          ),
        );
      } else if (notification.type == NotificationType.connectionRequest) {
        final profile = await ref.read(profileByIdProvider(fromId).future);
        if (profile == null || !context.mounted) return;
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserProfilePage(user: profile)),
        );
      }
    }

    final tappable = notification.type == NotificationType.message ||
        notification.type == NotificationType.connectionRequest;

    return InkWell(
      onTap: tappable ? onTap : null,
      child: Padding(
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
