import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:flutter/services.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/features/messaging/presentation/widgets/circle_nearby_row.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:echo/shared/widgets/navigation/floating_navbar.dart';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/messaging/presentation/pages/new_chat_page.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final conversationsAsync = ref.watch(conversationsProvider);

    final content = SafeArea(
      child: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        elevation: 0,
        onRefresh: () async {
          ref.invalidate(circleNearbyProvider);
          final _ = await ref.refresh(conversationsProvider.future);
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: CollapsingGlassHeaderDelegate(
                isDark: isDark,
                minExtent: 72,
                maxExtent: 96,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                pinnedGap: 0,
                pinned: (context) => Row(
                  children: [
                    Text(
                      'Messaggi',
                      style: AppTextStyles.displayLarge(context),
                    ),
                    const Spacer(),
                    GlassIconButton(
                      icon: Icons.add_rounded,
                      size: 42,
                      iconSize: 20,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NewChatPage()),
                      ),
                    ),
                  ],
                ),
                dissolving: (context) => const SizedBox.shrink(),
              ),
            ),
            if (isOnline) const SliverToBoxAdapter(child: CircleNearbyRow()),
            if (!isOnline)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: OfflinePlaceholder(
                  message: 'Torna online per accedere ai messaggi.',
                ),
              )
            else
              conversationsAsync.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SkeletonConversationList(),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Errore nel caricamento',
                          style: AppTextStyles.bodySecondary(context),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(conversationsProvider),
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (convs) => convs.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(isDark: isDark),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          bottom: FloatingNavbar.reservedHeight,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((ctx, i) {
                            return _ConversationTile(
                                  conversation: convs[i],
                                  isDark: isDark,
                                )
                                .animate(delay: (40 * (i < 10 ? i : 10)).ms)
                                .fadeIn(duration: 300.ms)
                                .slideX(
                                  begin: 0.04,
                                  end: 0,
                                  duration: 360.ms,
                                  curve: Curves.easeOutCubic,
                                );
                          }, childCount: convs.length),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      body: content,
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MingleLogomark(size: 80),
          const SizedBox(height: 16),
          Text(
            'Nessun messaggio ancora',
            style: AppTextStyles.body(context).copyWith(
              color: isDark
                  ? AppColors.textSecondaryLight
                  : AppColors.textSecondaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vai sul profilo di un contatto\nper iniziare a scrivere',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySecondary(context),
          ),
        ],
      ),
    );
  }
}

// ─── Conversation tile ────────────────────────────────────────────────────────

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation, required this.isDark});

  final ConversationModel conversation;
  final bool isDark;

  Future<void> _quickActions(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          value: 'location',
          label: 'Mandagli dove sei',
          icon: Icons.near_me_rounded,
        ),
        if (conversation.unreadCount > 0)
          const AdaptiveAction(
            value: 'read',
            label: 'Segna come letto',
            icon: Icons.done_all_rounded,
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    final repo = ref.read(messagingRepositoryProvider);
    try {
      if (action == 'read') {
        await repo.markMessagesRead(conversation.id);
      } else if (action == 'location') {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            timeLimit: Duration(seconds: 10),
          ),
        );
        String? label;
        try {
          final marks = await gc.placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          );
          if (marks.isNotEmpty) {
            final m = marks.first;
            label = [
              (m.street?.isNotEmpty ?? false) ? m.street : m.name,
              m.locality,
            ].whereType<String>().where((x) => x.trim().isNotEmpty).join(', ');
            if (label.isEmpty) label = null;
          }
        } catch (_) {}
        await repo.sendMessage(
          conversation.id,
          '',
          locationLat: pos.latitude,
          locationLng: pos.longitude,
          locationLabel: label,
        );
        if (context.mounted) {
          EchoToast.show(
            context,
            'Posizione inviata a ${conversation.otherName}',
            type: EchoToastType.success,
          );
        }
      }
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (context.mounted) {
        EchoToast.show(
          context,
          'Operazione non riuscita',
          type: EchoToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = conversation.unreadCount > 0;
    final previewStyle = AppTextStyles.bodySecondary(context).copyWith(
      fontSize: 14,
      fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
      color: unread ? AppColors.textLight : null,
    );

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatPage(conversation: conversation)),
      ),
      onLongPress: () => _quickActions(context, ref),
      splashColor: Colors.white.withValues(alpha: 0.04),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _Avatar(
              avatarUrl: conversation.otherAvatarUrl,
              name: conversation.otherName,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherName,
                    style: AppTextStyles.body(context).copyWith(
                      fontSize: 16,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  conversation.lastMessageIsGif ||
                          conversation.lastMessageIsDrop ||
                          conversation.lastMessageIsLocation
                      ? Row(
                          children: [
                            Icon(
                              conversation.lastMessageIsGif
                                  ? Icons.gif_box_outlined
                                  : conversation.lastMessageIsDrop
                                  ? Icons.grid_view_rounded
                                  : Icons.near_me_rounded,
                              size: 15,
                              color: previewStyle.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              conversation.lastMessageIsGif
                                  ? 'GIF'
                                  : conversation.lastMessageIsDrop
                                  ? 'Drop condiviso'
                                  : 'Posizione condivisa',
                              style: previewStyle,
                            ),
                          ],
                        )
                      : Text(
                          conversation.lastMessage?.isNotEmpty == true
                              ? conversation.lastMessage!
                              : 'Nessun messaggio',
                          style: previewStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (conversation.lastMessageAt != null)
                  Text(
                    _shortTime(conversation.lastMessageAt!),
                    style: AppTextStyles.bodySecondary(context).copyWith(
                      fontSize: 12,
                      color: unread ? AppColors.accent : null,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      conversation.unreadCount > 99
                          ? '99+'
                          : '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _shortTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    String two(int n) => n.toString().padLeft(2, '0');
    if (diff == 0) return '${two(local.hour)}:${two(local.minute)}';
    if (diff == 1) return 'ieri';
    if (diff < 7) {
      const days = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
      return days[local.weekday - 1];
    }
    if (local.year == now.year) return '${two(local.day)}/${two(local.month)}';
    return '${two(local.day)}/${two(local.month)}/${local.year % 100}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl, required this.name});

  final String? avatarUrl;
  final String name;

  static const _gradients = [
    [AppColors.accent, AppColors.accentSecondary],
    [AppColors.accentSecondary, AppColors.accent],
    [AppColors.accent, AppColors.blush],
    [AppColors.blush, AppColors.accentSecondary],
    [AppColors.accentSecondary, AppColors.blush],
  ];

  @override
  Widget build(BuildContext context) {
    const size = 54.0;
    if (avatarUrl != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.darkSurfaceLight,
        backgroundImage: CachedNetworkImageProvider(avatarUrl!),
      );
    }
    final g = _gradients[name.hashCode.abs() % _gradients.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g,
        ),
      ),
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );
  }
}
