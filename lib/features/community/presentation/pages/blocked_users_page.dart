import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utenti bloccati'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Errore nel caricamento',
            style: AppTextStyles.bodySecondary(context),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: 52,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun utente bloccato',
                    style: AppTextStyles.bodySecondary(context),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) =>
                _BlockedUserTile(user: users[i]),
          );
        },
      ),
    );
  }
}

class _BlockedUserTile extends ConsumerWidget {
  const _BlockedUserTile({required this.user});
  final ProfileModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        user.displayName.isNotEmpty ? user.displayName : user.username;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.accent.withValues(alpha: 0.18),
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null
            ? Text(
                name.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              )
            : null,
      ),
      title: Text(name, style: AppTextStyles.body(context)),
      subtitle: Text(
        '@${user.username}',
        style: AppTextStyles.bodySecondary(context),
      ),
      trailing: TextButton(
        onPressed: () => _unblock(context, ref),
        child: const Text(
          'Sblocca',
          style: TextStyle(color: AppColors.accent),
        ),
      ),
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(connectionRepositoryProvider);
    try {
      await repo.unblockUser(user.id);
      ref
        ..invalidate(blockedUsersProvider)
        ..invalidate(connectionStatusProvider(user.id));
      if (context.mounted) {
        EchoToast.show(context, 'Utente sbloccato', type: EchoToastType.info);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }
}
