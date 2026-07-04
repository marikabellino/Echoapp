import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Start a new chat: search among your connections, sorted by how much
/// you've interacted with them (most recent conversation first).
class NewChatPage extends ConsumerStatefulWidget {
  const NewChatPage({super.key});

  @override
  ConsumerState<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends ConsumerState<NewChatPage> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _starting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startChat(ProfileModel user) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final conversationId = await repo.getOrCreateConversation(user.id);
      final name = user.displayName.isNotEmpty
          ? user.displayName
          : user.username;
      final conversation = ConversationModel(
        id: conversationId,
        otherUserId: user.id,
        otherUsername: user.username,
        otherDisplayName: name,
        otherAvatarUrl: user.avatarUrl,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatPage(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connectionsAsync = ref.watch(myConnectionsProvider);
    final conversationsAsync = ref.watch(conversationsProvider);

    final content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildSearchBar(context, isDark),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: connectionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Errore nel caricamento',
                  style: AppTextStyles.bodySecondary(context),
                ),
              ),
              data: (connections) {
                final conversations = conversationsAsync.asData?.value ?? [];
                final lastMessageByUser = <String, DateTime>{
                  for (final c in conversations)
                    if (c.lastMessageAt != null)
                      c.otherUserId: c.lastMessageAt!,
                };

                final filtered = connections.where((u) {
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return u.username.toLowerCase().contains(q) ||
                      u.displayName.toLowerCase().contains(q);
                }).toList();

                filtered.sort((a, b) {
                  final da = lastMessageByUser[a.id];
                  final db = lastMessageByUser[b.id];
                  if (da != null && db != null) return db.compareTo(da);
                  if (da != null) return -1;
                  if (db != null) return 1;
                  final na = a.displayName.isNotEmpty
                      ? a.displayName
                      : a.username;
                  final nb = b.displayName.isNotEmpty
                      ? b.displayName
                      : b.username;
                  return na.toLowerCase().compareTo(nb.toLowerCase());
                });

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      connections.isEmpty
                          ? 'Non hai ancora collegamenti.'
                          : 'Nessun utente trovato.',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _UserRow(
                    user: filtered[i],
                    hasConversation: lastMessageByUser[filtered[i].id] != null,
                    isDark: isDark,
                    onTap: () => _startChat(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (isDark)
            const AnimatedGradientBackground(child: SizedBox.expand())
          else
            const ColoredBox(
              color: AppColors.lightBackground,
              child: SizedBox.expand(),
            ),
          content,
          if (_starting)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 19,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  textAlignVertical: TextAlignVertical.center,
                  style: AppTextStyles.body(context).copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Cerca tra i tuoi collegamenti',
                    hintStyle: AppTextStyles.bodySecondary(
                      context,
                    ).copyWith(fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User row ───────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.hasConversation,
    required this.isDark,
    required this.onTap,
  });

  final ProfileModel user;
  final bool hasConversation;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage: user.avatarUrl != null
                      ? CachedNetworkImageProvider(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '@${user.username}',
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (hasConversation)
                  Icon(
                    Icons.chat_bubble_rounded,
                    size: 17,
                    color: AppColors.textSecondaryDark.withValues(alpha: 0.5),
                    
                  )
                else
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.accentSecondary],
                      ),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: Colors.white,
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
