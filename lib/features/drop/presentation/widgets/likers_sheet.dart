import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Likers sheet: chi ha messo like a un drop ─────────────────────────────────

class LikersSheet extends ConsumerWidget {
  const LikersSheet({super.key, required this.dropId});
  final String dropId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likersAsync = ref.watch(likersProvider(dropId));

    return EchoBottomSheet(
      height: MediaQuery.of(context).size.height * 0.6,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Piace a', style: AppTextStyles.headline(context)),
              ),
            ),
            Expanded(
              child: likersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Errore nel caricamento',
                    style: AppTextStyles.bodySecondary(context),
                  ),
                ),
                data: (likers) {
                  if (likers.isEmpty) {
                    return Center(
                      child: Text(
                        'Nessun like ancora.',
                        style: AppTextStyles.bodySecondary(context),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: likers.length,
                    itemBuilder: (context, i) => _LikerTile(user: likers[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikerTile extends StatelessWidget {
  const _LikerTile({required this.user});
  final ProfileModel user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    return ListTile(
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserProfilePage(user: user)),
        );
      },
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null
            ? Text(
                name.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(name, style: AppTextStyles.body(context)),
      subtitle: Text(
        '@${user.username}',
        style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 12),
      ),
    );
  }
}
