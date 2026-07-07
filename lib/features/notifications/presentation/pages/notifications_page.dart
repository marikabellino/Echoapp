import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifications = ref.watch(notificationsProvider);

    final content = SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingGlassHeaderDelegate(
              isDark: isDark,
              minExtent: 52,
              maxExtent: 72,
              padding: const EdgeInsets.fromLTRB(12, 16, 20, 8),
              pinnedGap: 0,
              pinned: (context) => Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Notifiche',
                    style: GoogleFonts.nunito(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          ref.read(notificationsProvider.notifier).clear(),
                      child: Text(
                        'Cancella tutto',
                        style: AppTextStyles.bodySecondary(context).copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
              dissolving: (context) => const SizedBox.shrink(),
            ),
          ),
          if (notifications.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverPadding(
              padding: EdgeInsets.only(
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Column(
                    children: [
                      _NotificationTile(notification: notifications[i]),
                      if (i < notifications.length - 1)
                        const Divider(height: 1, thickness: 0.4, indent: 64),
                    ],
                  ),
                  childCount: notifications.length,
                ),
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: isDark
          ? AnimatedGradientBackground(child: content)
          : ColoredBox(color: AppColors.lightBackground, child: content),
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
      NotificationType.connectionRequest => (
        LucideIcons.userPlus,
        AppColors.accent,
      ),
      NotificationType.proximity => (
        LucideIcons.mapPin,
        const Color(0xFF5BC4B0),
      ),
      NotificationType.message => (
        LucideIcons.messageCircle,
        const Color(0xFF7B9CFF),
      ),
      NotificationType.tagged => (LucideIcons.atSign, AppColors.accent),
    };

    Future<void> onTap() async {
      final fromId = notification.fromUserId;

      if (notification.type == NotificationType.message) {
        if (fromId == null) return;
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
      } else if (notification.type == NotificationType.connectionRequest ||
          notification.type == NotificationType.like) {
        if (fromId == null) return;
        final profile = await ref.read(profileByIdProvider(fromId).future);
        if (profile == null || !context.mounted) return;
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserProfilePage(user: profile)),
        );
      } else if (notification.type == NotificationType.proximity ||
          notification.type == NotificationType.tagged) {
        final dropId = notification.dropId;
        if (dropId == null) return;
        final drop = await ref.read(dropByIdProvider(dropId).future);
        if (drop == null || !context.mounted) return;
        Navigator.of(context).pop();
        ref.read(mapFlyTargetProvider.notifier).set(drop);
        ref.read(shellIndexProvider.notifier).setIndex(1);
      }
    }

    final tappable =
        notification.type == NotificationType.message ||
        notification.type == NotificationType.connectionRequest ||
        notification.type == NotificationType.like ||
        notification.type == NotificationType.proximity ||
        notification.type == NotificationType.tagged;

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
                    style: AppTextStyles.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: AppTextStyles.bodySecondary(
                      context,
                    ).copyWith(fontSize: 13),
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
  const _EmptyState();

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
