import 'package:flutter/services.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/avatar_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'package:echo/features/profile/presentation/widgets/profile_widgets.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ─── Blocked-by-them view ──────────────────────────────────────────────────────

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                Icon(
                  LucideIcons.userX,
                  size: 56,
                  color: (isDark ? AppColors.textLight : AppColors.textDark)
                      .withValues(alpha: 0.25),
                ),
                const SizedBox(height: 20),
                Text(
                  'Utente non disponibile',
                  style: AppTextStyles.headline(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Non puoi visualizzare questo profilo.',
                  style: AppTextStyles.bodySecondary(context),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.user});

  final ProfileModel user;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  final _scroll = ScrollController();

  bool _showFloating = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset < 60;
      if (show != _showFloating) setState(() => _showFloating = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ProfileModel get user => widget.user;

  void _openDrop(DropModel drop) {
    openDropDetail(context, drop);
  }

  String? _coverUrl(List<DropModel>? drops) {
    final withPhoto = drops?.where((d) => d.imageUrl != null);
    if (withPhoto != null && withPhoto.isNotEmpty) {
      return withPhoto.first.imageUrl;
    }
    return user.avatarUrl;
  }

  int _placesCount(List<DropModel>? drops) => (drops ?? const [])
      .map(
        (d) =>
            '${d.latitude.toStringAsFixed(3)},${d.longitude.toStringAsFixed(3)}',
      )
      .toSet()
      .length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusAsync = ref.watch(connectionStatusProvider(user.id));

    if (statusAsync.asData?.value == ConnectionStatus.blockedByThem) {
      return _UnavailableView(isDark: isDark);
    }

    final dropsAsync = ref.watch(userDropsProvider(user.id));
    final drops = dropsAsync.asData?.value;
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    final isOwnProfile = ref.watch(currentUserProvider)?.id == user.id;
    final isConnected = statusAsync.asData?.value == ConnectionStatus.connected;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ProfileCover(
                  imageUrl: _coverUrl(drops),
                  topInset: topInset,
                  child: Column(
                    children: [
                      const SizedBox(height: 56),
                      GestureDetector(
                            onTap: user.avatarUrl != null
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AvatarDetailPage(
                                        imageUrl: user.avatarUrl!,
                                        heroTag: 'avatar-${user.id}',
                                      ),
                                    ),
                                  )
                                : null,
                            child: Hero(
                              tag: 'avatar-${user.id}',
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 44,
                                  backgroundColor: AppColors.accent.withValues(
                                    alpha: 0.25,
                                  ),
                                  backgroundImage: user.avatarUrl != null
                                      ? CachedNetworkImageProvider(
                                          user.avatarUrl!,
                                        )
                                      : null,
                                  child: user.avatarUrl == null
                                      ? Text(
                                          name.characters.first.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .scale(
                            begin: const Offset(0.9, 0.9),
                            curve: Curves.easeOutBack,
                            duration: 500.ms,
                          ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            name,
                            maxLines: 1,
                            style: AppTextStyles.headline(context).copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      if (user.bio.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            user.bio,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body(
                              context,
                            ).copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GlassPanel(
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Expanded(
                                  child: StatItem(
                                    value: user.dropsCount,
                                    label: 'drop',
                                  ),
                                ),
                                const StatDivider(),
                                Expanded(
                                  child: StatItem(
                                    value: user.connectionsCount,
                                    label: 'cerchia',
                                  ),
                                ),
                                const StatDivider(),
                                Expanded(
                                  child: StatItem(
                                    value: _placesCount(drops),
                                    label: 'posti',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (user.distanceKm != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.near_me_rounded,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              user.distanceKm! < 1
                                  ? 'a meno di 1 km da te'
                                  : 'a ${user.distanceKm!.toStringAsFixed(1)} km da te',
                              style: AppTextStyles.bodySecondary(context)
                                  .copyWith(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        ),
                      ],
                      if (!isOwnProfile) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(child: _ConnectButton(userId: user.id)),
                              if (isConnected) ...[
                                const SizedBox(width: 10),
                                Expanded(child: _MessageButton(user: user)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              dropsAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 120),
                    child: SkeletonDropsGrid(wrapInLoader: true),
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
                data: (drops) {
                  if (drops.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Text(
                          'Nessun drop ancora.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySecondary(context),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            _DropCard(drop: drops[i], onTap: _openDrop)
                                .animate(delay: (30 * (i < 15 ? i : 15)).ms)
                                .fadeIn(duration: 320.ms)
                                .scale(
                                  begin: const Offset(0.92, 0.92),
                                  curve: Curves.easeOutCubic,
                                  duration: 320.ms,
                                ),
                        childCount: drops.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 3,
                            mainAxisSpacing: 3,
                          ),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: topInset + 4,
            left: 8,
            right: 8,
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (!isOwnProfile) _MoreOptionsButton(user: user),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Drop card (grid) ───────────────────────────────────────────────────────

class _DropCard extends ConsumerWidget {
  const _DropCard({required this.drop, required this.onTap});
  final DropModel drop;
  final void Function(DropModel) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropGridTile(
      drop: drop,
      onTap: () => onTap(drop),
      onLongPress: () => _showOptions(context, ref),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: const [
        AdaptiveAction(
          value: 'report',
          label: 'Segnala post',
          icon: Icons.flag_outlined,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Segnala post',
      message:
          'Sei sicuro di voler segnalare questo contenuto? Lo esamineremo quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dropRepositoryProvider).reportDrop(drop.id);
      if (context.mounted) {
        EchoToast.show(
          context,
          'Segnalazione inviata. Grazie.',
          type: EchoToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }
}

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider(userId));

    return statusAsync.when(
      loading: () => const MingleLoader(size: 34),
      error: (_, _) => const SizedBox.shrink(),
      data: (status) {
        if (status == ConnectionStatus.blocked ||
            status == ConnectionStatus.blockedByThem) {
          return const SizedBox.shrink();
        }

        final (label, icon, filled) = switch (status) {
          ConnectionStatus.none => (
            'Connetti',
            Icons.person_add_outlined,
            true,
          ),
          ConnectionStatus.pendingSent => (
            'In attesa',
            Icons.hourglass_empty_outlined,
            false,
          ),
          ConnectionStatus.pendingReceived => (
            'Accetta',
            Icons.check_circle_outline,
            true,
          ),
          ConnectionStatus.connected => (
            'Nella cerchia',
            Icons.people_outlined,
            false,
          ),
          ConnectionStatus.blocked => ('', Icons.block, false),
          ConnectionStatus.blockedByThem => ('', Icons.block, false),
        };

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _onTap(context, ref, status);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              color: filled
                  ? AppColors.accent
                  : Colors.white.withValues(alpha: 0.10),
              border: filled
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
          final confirmed = await showAdaptiveConfirmDialog(
            context: context,
            title: 'Rimuovere dalla cerchia?',
            message:
                'Non vedrete più i drop riservati alla cerchia l\'uno dell\'altro.',
            confirmLabel: 'Rimuovi',
            cancelLabel: 'Annulla',
            destructive: true,
          );
          if (confirmed != true) return;
          await repo.removeConnection(userId);
        case ConnectionStatus.blocked:
        case ConnectionStatus.blockedByThem:
          break;
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
        if (status != ConnectionStatus.connected)
          return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _openChat(context, ref);
          },
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              color: AppColors.accent,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.messageCircle, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Messaggio',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(conversation: conversation),
          ),
        );
      }
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
}

// ─── More options (block / unblock) ──────────────────────────────────────────

class _MoreOptionsButton extends ConsumerWidget {
  const _MoreOptionsButton({required this.user});
  final ProfileModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider(user.id));
    final isBlocked = statusAsync.asData?.value == ConnectionStatus.blocked;

    return GlassIconButton(
      icon: Icons.more_horiz_rounded,
      onPressed: () => _showSheet(context, ref, isBlocked),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref, bool isBlocked) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        AdaptiveAction(
          value: isBlocked ? 'unblock' : 'block',
          label: isBlocked ? 'Sblocca utente' : 'Blocca utente',
          icon: isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
          isDestructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'block') {
      _confirmBlock(context, ref);
    } else {
      _unblock(context, ref);
    }
  }

  void _confirmBlock(BuildContext context, WidgetRef ref) async {
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Blocca utente',
      message:
          'Vuoi bloccare $name? Non potrà più trovarti o connettersi con te.',
      confirmLabel: 'Blocca',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed == true && context.mounted) _block(context, ref);
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(connectionRepositoryProvider);
    try {
      await repo.blockUser(user.id);
      ref.invalidate(connectionStatusProvider(user.id));
      ref.invalidate(conversationsProvider);
      ref.invalidate(discoverProvider);
      ref.invalidate(nearbyDropsProvider);
      ref.invalidate(myConnectionsProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Utente bloccato', type: EchoToastType.info);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(connectionRepositoryProvider);
    try {
      await repo.unblockUser(user.id);
      ref.invalidate(connectionStatusProvider(user.id));
      ref.invalidate(conversationsProvider);
      ref.invalidate(discoverProvider);
      ref.invalidate(nearbyDropsProvider);
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

// ─── Background ───────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (isDark) {
      return const AnimatedGradientBackground(child: SizedBox.expand());
    }
    return Container(
      decoration: const BoxDecoration(color: AppColors.lightBackground),
    );
  }
}
