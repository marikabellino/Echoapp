import 'package:apptest/core/theme/app_colors.dart';
import 'package:apptest/core/theme/app_text_styles.dart';
import 'package:apptest/features/community/providers/connection_provider.dart';
import 'package:apptest/features/memory/domain/models/memory_model.dart';
import 'package:apptest/features/memory/providers/memory_provider.dart';
import 'package:apptest/features/messaging/domain/models/conversation_model.dart';
import 'package:apptest/features/messaging/presentation/pages/chat_page.dart';
import 'package:apptest/features/messaging/providers/messaging_provider.dart';
import 'package:apptest/features/profile/domain/models/profile_model.dart';
import 'package:apptest/shared/widgets/echo_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.user});

  final ProfileModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final memoriesAsync = ref.watch(userMemoriesProvider(user.id));
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar
                              CircleAvatar(
                                radius: 40,
                                backgroundColor:
                                    const Color(0xFF7EB8D4).withValues(alpha: 0.25),
                                backgroundImage: user.avatarUrl != null
                                    ? CachedNetworkImageProvider(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? Text(
                                        name.characters.first.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF7EB8D4),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      name,
                                      style: AppTextStyles.headline(context),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '@${user.username}',
                                      style: AppTextStyles.bodySecondary(context),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${user.memoriesCount}',
                                              style:
                                                  AppTextStyles.headline(context),
                                            ),
                                            Text(
                                              'ricordi',
                                              style: AppTextStyles.bodySecondary(
                                                  context),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 24),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${user.connectionsCount}',
                                              style: AppTextStyles.headline(
                                                  context),
                                            ),
                                            Text(
                                              'cerchia',
                                              style: AppTextStyles.bodySecondary(
                                                  context),
                                            ),
                                          ],
                                        ),
                                        if (user.distanceKm != null) ...[
                                          const SizedBox(width: 24),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user.distanceKm! < 1
                                                    ? '< 1 km'
                                                    : '${user.distanceKm!.toStringAsFixed(1)} km',
                                                style: AppTextStyles.headline(
                                                    context),
                                              ),
                                              Text(
                                                'da te',
                                                style: AppTextStyles.bodySecondary(
                                                    context),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        _ConnectButton(userId: user.id),
                                        const SizedBox(width: 8),
                                        _MessageButton(user: user),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (user.bio.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              user.bio,
                              style: AppTextStyles.body(context),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            'Ricordi di $name',
                            style: AppTextStyles.headline(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              memoriesAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                    heightFactor: 4,
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, _) => SliverToBoxAdapter(
                  child: Center(
                    child: Text(
                      'Errore nel caricamento',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ),
                ),
                data: (memories) {
                  if (memories.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.location_off_outlined,
                              size: 48,
                              color: Colors.white30,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nessun ricordo ancora.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _MemoryCard(memory: memories[i]),
                        childCount: memories.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.9,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Memory card (grid) ───────────────────────────────────────────────────────

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory});
  final MemoryModel memory;

  @override
  Widget build(BuildContext context) {
    final hasImage = memory.imageUrl != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            CachedNetworkImage(
              imageUrl: memory.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => _MoodBackground(mood: memory.mood),
              errorWidget: (_, _, _) => _MoodBackground(mood: memory.mood),
            )
          else
            _MoodBackground(mood: memory.mood),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.35, 1.0],
                colors: [Colors.transparent, Color(0xC5000000)],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: memory.mood.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: memory.mood.color.withValues(alpha: 0.7),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Icon(
              memory.visibility.icon,
              size: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  memory.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (memory.locationName != null) ...[
                      Icon(Icons.location_on_outlined,
                          size: 10,
                          color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          memory.locationName!,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      timeago.format(memory.createdAt, locale: 'it'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10),
                    ),
                    const Spacer(),
                    Icon(Icons.favorite_border,
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text(
                      '${memory.likesCount}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodBackground extends StatelessWidget {
  const _MoodBackground({required this.mood});
  final MemoryMood mood;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            mood.color.withValues(alpha: 0.45),
            mood.color.withValues(alpha: 0.12),
          ],
        ),
      ),
    );
  }
}

// ─── Connect button ───────────────────────────────────────────────────────────

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider(userId));

    return statusAsync.when(
      loading: () => const SizedBox(
        height: 34,
        width: 34,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (status) {
        final (label, icon, filled) = switch (status) {
          ConnectionStatus.none => ('Connetti', Icons.person_add_outlined, true),
          ConnectionStatus.pendingSent => ('In attesa', Icons.hourglass_empty_outlined, false),
          ConnectionStatus.pendingReceived => ('Accetta', Icons.check_circle_outline, true),
          ConnectionStatus.connected => ('Cerchia ✓', Icons.people_outlined, false),
        };

        return GestureDetector(
          onTap: () => _onTap(context, ref, status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: filled
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: filled
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    ConnectionStatus status,
  ) async {
    final repo = ref.read(connectionRepositoryProvider);
    try {
      switch (status) {
        case ConnectionStatus.none:
          await repo.sendRequest(userId);
        case ConnectionStatus.pendingSent:
          await repo.removeConnection(userId);
        case ConnectionStatus.pendingReceived:
          await repo.acceptRequest(userId);
        case ConnectionStatus.connected:
          await repo.removeConnection(userId);
      }
      ref.invalidate(connectionStatusProvider(userId));
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }
}

// ─── Message button ───────────────────────────────────────────────────────────

class _MessageButton extends ConsumerWidget {
  const _MessageButton({required this.user});
  final ProfileModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider(user.id));

    return statusAsync.maybeWhen(
      data: (status) {
        if (status != ConnectionStatus.connected) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _openChat(context, ref),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.accent.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.messageCircle,
                    size: 15, color: AppColors.accent),
                const SizedBox(width: 6),
                const Text(
                  'Messaggio',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(messagingRepositoryProvider);
    try {
      final conversationId = await repo.getOrCreateConversation(user.id);
      final name = user.displayName.isNotEmpty ? user.displayName : user.username;
      final conversation = ConversationModel(
        id: conversationId,
        otherUserId: user.id,
        otherUsername: user.username,
        otherDisplayName: name,
        otherAvatarUrl: user.avatarUrl,
      );
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF100F1C), Color(0xFF181528), Color(0xFF100E1A)]
              : const [Color(0xFFF3F1FC), Color(0xFFE9E6F7), Color(0xFFF8F9FB)],
        ),
      ),
    );
  }
}
