import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/services/location_service.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CircleFriend = ({ProfileModel profile, double? km});

class ShareDistanceNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      final v = await ref
          .read(supabaseClientProvider)
          .rpc('get_my_share_distance');
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> set(bool enabled) async {
    try {
      await ref
          .read(supabaseClientProvider)
          .rpc('set_share_distance', params: {'enabled': enabled});
      state = AsyncData(enabled);
      ref.invalidate(circleNearbyProvider);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final shareDistanceProvider =
    AsyncNotifierProvider<ShareDistanceNotifier, bool>(
      ShareDistanceNotifier.new,
    );

Future<void> toggleShareDistance(
  BuildContext context,
  WidgetRef ref, {
  required bool enable,
}) async {
  final confirmed = await showAdaptiveConfirmDialog(
    context: context,
    title: enable ? 'Mostrare la tua distanza?' : 'Nascondere la tua distanza?',
    message: enable
        ? 'Gli amici della tua cerchia vedranno quanto sei lontano (mai la posizione esatta), solo se anche loro condividono la loro. Puoi disattivarlo quando vuoi dalle impostazioni.'
        : 'La cerchia non vedrà più la tua distanza e tu non vedrai più la loro.',
    confirmLabel: enable ? 'Attiva' : 'Disattiva',
    cancelLabel: 'Annulla',
  );
  if (confirmed != true) return;
  final ok = await ref.read(shareDistanceProvider.notifier).set(enable);
  if (!context.mounted) return;
  EchoToast.show(
    context,
    ok
        ? (enable ? 'Distanza condivisa con la cerchia' : 'Distanza nascosta')
        : 'Funzione non ancora disponibile',
    type: ok ? EchoToastType.success : EchoToastType.error,
  );
}

final circleNearbyProvider = FutureProvider.autoDispose<List<CircleFriend>>((
  ref,
) async {
  final pos = await ref.watch(userPositionProvider.future);
  final client = ref.watch(supabaseClientProvider);
  final sharing = await ref.watch(shareDistanceProvider.future);
  if (pos != null && sharing) {
    ref
        .read(profileRepositoryProvider)
        .updateLocation(pos.latitude, pos.longitude)
        .ignore();
  }
  try {
    final rows = await client.rpc(
      'get_circle_nearby',
      params: {'user_lat': pos?.latitude, 'user_lng': pos?.longitude},
    );
    return [
      for (final r in rows as List<dynamic>)
        (
          profile: ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)),
          km: ((r)['distance_km'] as num?)?.toDouble(),
        ),
    ];
  } catch (_) {
    final list = await ref.watch(myConnectionsProvider.future);
    return [for (final p in list) (profile: p, km: null)];
  }
});

String? _distanceLabel(double? km) {
  if (km == null) return null;
  if (km < 1) return 'qui vicino';
  return 'circa ${km.round()} km';
}

class CircleNearbyRow extends ConsumerWidget {
  const CircleNearbyRow({super.key});

  Future<void> _openChat(
    BuildContext context,
    WidgetRef ref,
    ProfileModel user,
  ) async {
    HapticFeedback.selectionClick();
    try {
      final id = await ref
          .read(messagingRepositoryProvider)
          .getOrCreateConversation(user.id);
      final name = user.displayName.isNotEmpty
          ? user.displayName
          : user.username;
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversation: ConversationModel(
              id: id,
              otherUserId: user.id,
              otherUsername: user.username,
              otherDisplayName: name,
              otherAvatarUrl: user.avatarUrl,
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(
          context,
          e is MessagingException ? e.message : 'Errore: $e',
          type: EchoToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(circleNearbyProvider).asData?.value;
    if (friends == null || friends.isEmpty) return const SizedBox.shrink();
    final near = friends.where((f) => f.km != null && f.km! < 1).length;
    final sharing = ref.watch(shareDistanceProvider).asData?.value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  near > 0
                      ? '$near ${near == 1 ? 'amico è' : 'amici sono'} qui vicino'
                      : 'La tua cerchia',
                  style: AppTextStyles.bodySecondary(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!sharing)
                GestureDetector(
                  onTap: () => toggleShareDistance(context, ref, enable: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.near_me_rounded,
                          size: 13,
                          color: AppColors.accent,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Vedi chi è vicino',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: friends.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final f = friends[i];
              return _FriendBubble(
                    friend: f,
                    onTap: () => _openChat(context, ref, f.profile),
                  )
                  .animate(delay: (40 * (i < 10 ? i : 10)).ms)
                  .fadeIn(duration: 280.ms)
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    duration: 360.ms,
                    curve: Curves.easeOutBack,
                  );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
          child: Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }
}

class _FriendBubble extends StatelessWidget {
  const _FriendBubble({required this.friend, required this.onTap});
  final CircleFriend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = friend.profile;
    final label = _distanceLabel(friend.km);
    final close = friend.km != null && friend.km! < 1;
    final name = p.displayName.isNotEmpty ? p.displayName : p.username;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: close ? AppColors.brandGradient : null,
                    border: close
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                  ),
                  child: ClipOval(
                    child: p.avatarUrl != null && p.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: p.avatarUrl!,
                            memCacheWidth: 200,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _Initial(name: name),
                          )
                        : _Initial(name: name),
                  ),
                ),
                if (label != null)
                  Positioned(
                    bottom: -6,
                    left: -6,
                    right: -6,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: close
                              ? AppColors.accent
                              : AppColors.darkSurfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.darkBackground,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
