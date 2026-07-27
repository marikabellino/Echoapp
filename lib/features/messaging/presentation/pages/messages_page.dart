import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/messaging/presentation/pages/new_chat_page.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

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
        onRefresh: () => ref.refresh(conversationsProvider.future),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((ctx, i) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ConversationTile(
                                conversation: convs[i],
                                isDark: isDark,
                              ),
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
      body: isDark ? AnimatedGradientBackground(child: content) : content,
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
          Icon(
            LucideIcons.messageCircle,
            size: 56,
            color: AppColors.accent.withValues(alpha: 0.4),
          ),
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.isDark});

  final ConversationModel conversation;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatPage(conversation: conversation)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              // Colori fissi e neutri — il tema Material è generato da un
              // seed rosa, quindi i grigi "neutri" del tema portano comunque
              // una tinta rosata.
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.55)
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                _Avatar(
                  avatarUrl: conversation.otherAvatarUrl,
                  name: conversation.otherName,
                  unreadCount: conversation.unreadCount,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.otherName,
                              style: AppTextStyles.body(context).copyWith(
                                fontWeight: conversation.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (conversation.lastMessageAt != null)
                            Text(
                              timeago.format(
                                conversation.lastMessageAt!,
                                locale: 'it',
                              ),
                              style: AppTextStyles.bodySecondary(
                                context,
                              ).copyWith(fontSize: 11),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final previewStyle = AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: conversation.unreadCount > 0
                                ? (isDark
                                      ? AppColors.textLight
                                      : AppColors.textDark)
                                : null,
                          );
                          // Un messaggio-GIF ha testo vuoto: senza questo
                          // controllo la riga risultava vuota invece di
                          // segnalare che l'ultimo messaggio è una GIF.
                          if (conversation.lastMessageIsGif) {
                            return Row(
                              children: [
                                Icon(
                                  Icons.gif_box_outlined,
                                  size: 15,
                                  color: previewStyle.color,
                                ),
                                const SizedBox(width: 3),
                                Text('GIF', style: previewStyle),
                              ],
                            );
                          }
                          return Text(
                            conversation.lastMessage?.isNotEmpty == true
                                ? conversation.lastMessage!
                                : 'Nessun messaggio',
                            style: previewStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.name,
    required this.unreadCount,
    required this.isDark,
  });

  final String? avatarUrl;
  final String name;
  final int unreadCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.accent.withValues(alpha: 0.15),
          backgroundImage: avatarUrl != null
              ? CachedNetworkImageProvider(avatarUrl!)
              : null,
          child: avatarUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                )
              : null,
        ),
        if (unreadCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkBackground
                      : AppColors.lightBackground,
                  width: 1.5,
                ),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
