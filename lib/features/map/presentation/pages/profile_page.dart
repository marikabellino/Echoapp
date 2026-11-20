import 'package:echo/features/settings/presentation/pages/settings_page.dart';
import 'dart:io';

import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:flutter/cupertino.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/features/notifications/presentation/pages/notifications_page.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart'
    as messaging;
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:echo/shared/widgets/avatar_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'package:echo/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:echo/features/profile/presentation/widgets/profile_widgets.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final profileAsync = ref.watch(currentProfileProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _Background(isDark: isDark),
          if (!isOnline)
            const OfflinePlaceholder(
              message: 'Torna online per accedere al tuo profilo.',
            )
          else
            profileAsync.when(
              loading: () => const SkeletonProfilePage(),
              error: (e, _) => Center(
                child: Text('Errore: $e', style: AppTextStyles.body(context)),
              ),
              data: (profile) {
                if (profile == null) {
                  if (user == null) {
                    // Utente appena sloggato: schermata di transizione in
                    // attesa che GoRouter completi il redirect a /login.
                    return const SkeletonProfilePage();
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Profilo non trovato',
                          style: AppTextStyles.body(context),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () async {
                            await ref.read(authRepositoryProvider).signOut();
                            ref.invalidate(messaging.conversationsProvider);
                            ref.invalidate(notificationsProvider);
                            ref.invalidate(currentProfileProvider);
                            ref.invalidate(myConnectionsProvider);
                            ref.invalidate(pendingRequestsProvider);
                          },
                          child: const Text('Esci'),
                        ),
                      ],
                    ),
                  );
                }
                return _ProfileBody(profile: profile, userId: user?.id ?? '');
              },
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + 12,
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
        ],
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile, required this.userId});

  final ProfileModel profile;
  final String userId;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  int _tab = 0;

  ProfileModel get profile => widget.profile;
  String get userId => widget.userId;

  String? _coverUrl(List<DropModel>? drops) {
    final withPhoto = drops?.where((d) => d.imageUrl != null);
    if (withPhoto != null && withPhoto.isNotEmpty) {
      return withPhoto.first.imageUrl;
    }
    return profile.avatarUrl;
  }

  int _placesCount(List<DropModel>? drops) => (drops ?? const [])
      .map(
        (d) =>
            '${d.latitude.toStringAsFixed(3)},${d.longitude.toStringAsFixed(3)}',
      )
      .toSet()
      .length;

  void _openDrop(DropModel drop) {
    openDropDetail(context, drop);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final dropsAsync = ref.watch(userDropsProvider(userId));
    final taggedDropsAsync = ref.watch(taggedDropsProvider(userId));
    final pendingCount =
        ref.watch(pendingRequestsProvider).asData?.value.length ?? 0;

    return SafeArea(
      top: false,
      child: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        elevation: 0,
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: () => Future.wait([
          ref.refresh(currentProfileProvider.future),
          ref.refresh(userDropsProvider(userId).future),
          ref.refresh(taggedDropsProvider(userId).future),
        ]),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: ProfileCover(
                imageUrl: _coverUrl(dropsAsync.asData?.value),
                topInset: MediaQuery.paddingOf(context).top,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                      child: Row(
                        children: [
                          const MingleWordmark(
                            fontSize: 18,
                            color: AppColors.accent,
                            dotColor: AppColors.accentSecondary,
                          ),
                          const Spacer(),
                          _BellButton(onTap: () => _showNotifications(context)),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            color: Colors.white,
                            onPressed: () => _showSettings(context, ref),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AvatarWidget(profile: profile)
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
                          profile.displayName.isNotEmpty
                              ? profile.displayName
                              : profile.username,
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
                      '@${profile.username}',
                      style: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          profile.bio,
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
                                  value: profile.dropsCount,
                                  label: 'drop',
                                ),
                              ),
                              const StatDivider(),
                              Expanded(
                                child: StatItem(
                                  value: profile.connectionsCount,
                                  label: 'cerchia',
                                  badge: pendingCount,
                                  onTap: () => _showCircleSheet(context, ref),
                                ),
                              ),
                              const StatDivider(),
                              Expanded(
                                child: StatItem(
                                  value: _placesCount(dropsAsync.asData?.value),
                                  label: 'posti',
                                  onTap: () => setState(() => _tab = 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GlassButton(
                        label: isOnline ? 'Modifica profilo' : 'Offline',
                        onTap: isOnline
                            ? () => _showEditProfile(context, ref, profile)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileTabsDelegate(
                topInset: MediaQuery.paddingOf(context).top,
                index: _tab,
                onTap: (i) => setState(() => _tab = i),
                labels: [
                  'Drop',
                  'Mappa',
                  'Taggato${(taggedDropsAsync.asData?.value.length ?? 0) > 0 ? ' · ${taggedDropsAsync.asData!.value.length}' : ''}',
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            if (_tab == 0)
              _dropsGrid(
                context,
                dropsAsync,
                (d) => _DropCard(drop: d),
                emptyText:
                    'Nessun drop ancora.\nVai sulla mappa e lascia il primo!',
              )
            else if (_tab == 1)
              dropsAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: Center(child: MingleLoader()),
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
                data: (drops) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: ProfileDropsMap(drops: drops, onDropTap: _openDrop),
                  ),
                ),
              )
            else
              _dropsGrid(
                context,
                taggedDropsAsync,
                (d) => _TaggedDropCard(drop: d, userId: userId),
                emptyText: 'Nessun drop tra i taggati.',
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _dropsGrid(
    BuildContext context,
    AsyncValue<List<DropModel>> async,
    Widget Function(DropModel) tile, {
    required String emptyText,
  }) {
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                emptyText,
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
              (context, i) => tile(drops[i])
                  .animate(delay: (30 * (i < 15 ? i : 15)).ms)
                  .fadeIn(duration: 320.ms)
                  .scale(
                    begin: const Offset(0.92, 0.92),
                    curve: Curves.easeOutCubic,
                    duration: 320.ms,
                  ),
              childCount: drops.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
          ),
        );
      },
    );
  }

  void _showNotifications(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }

  void _showCircleSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => const _CircleSheet(),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onEditProfile: () => _showEditProfile(context, ref, profile),
        ),
      ),
    );
  }

  void _showEditProfile(
    BuildContext context,
    WidgetRef ref,
    ProfileModel profile,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: profile)),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _AvatarWidget extends ConsumerStatefulWidget {
  const _AvatarWidget({required this.profile});
  final ProfileModel profile;

  @override
  ConsumerState<_AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends ConsumerState<_AvatarWidget> {
  bool _uploading = false;

  static const String _heroPrefix = 'avatar-';

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final heroTag = '$_heroPrefix${profile.id}';
    return Stack(
      children: [
        GestureDetector(
          onTap: _uploading
              ? null
              : () => profile.avatarUrl != null
                    ? _openDetail(context, profile.avatarUrl!, heroTag)
                    : _pickAvatar(context),
          child: Hero(
            tag: heroTag,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              backgroundImage: profile.avatarUrl != null
                  ? CachedNetworkImageProvider(profile.avatarUrl!)
                  : null,
              child: _uploading
                  ? const MingleLoader(size: 30)
                  : profile.avatarUrl == null
                  ? Text(
                      ((profile.displayName.isNotEmpty
                                      ? profile.displayName
                                      : profile.username)
                                  .characters
                                  .firstOrNull ??
                              '?')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        if (!_uploading)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _pickAvatar(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openDetail(BuildContext context, String imageUrl, String heroTag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarDetailPage(imageUrl: imageUrl, heroTag: heroTag),
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    ImageSource? source;

    if (Platform.isIOS || Platform.isMacOS) {
      source = await showCupertinoModalPopup<ImageSource>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
              child: const Text('Scatta una foto'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
              child: const Text('Scegli dalla libreria'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
        ),
      );
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black54,
        builder: (ctx) => EchoBottomSheet(
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Scatta una foto'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Scegli dalla galleria'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }

    if (source == null || !context.mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 400,
    );
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(currentProfileProvider.notifier)
          .uploadAvatar(bytes);
      await ref
          .read(currentProfileProvider.notifier)
          .saveProfile(
            displayName: widget.profile.displayName,
            bio: widget.profile.bio,
            avatarUrl: url,
          );
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore upload: $e', type: EchoToastType.error);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

// ─── Drop card (grid) ───────────────────────────────────────────────────────

class _DropCard extends ConsumerWidget {
  const _DropCard({required this.drop});
  final DropModel drop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropGridTile(
      drop: drop,
      onTap: () => _showDropDetail(context, ref),
      onLongPress: () => _showOptions(context, ref),
    );
  }

  void _showDropDetail(BuildContext context, WidgetRef ref) {
    openDropDetail(context, drop);
  }

  void _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          value: 'delete',
          label: 'Elimina drop',
          icon: Icons.delete_outline,
          isDestructive: true,
        ),
        const AdaptiveAction(
          value: 'report',
          label: 'Segnala post',
          icon: Icons.flag_outlined,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') _confirmDelete(context, ref);
    if (action == 'report') _confirmReport(context, ref);
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina drop',
      message:
          'Sei sicuro di voler eliminare questo drop? L\'azione non è reversibile.',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(dropRepositoryProvider)
          .deleteDrop(drop.id, imageUrl: drop.imageUrl);
      ref.invalidate(userDropsProvider(drop.userId));
      ref.invalidate(discoverProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Drop eliminato.', type: EchoToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  void _confirmReport(BuildContext context, WidgetRef ref) async {
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

// ─── Tagged drop card (grid, "Taggato in") ────────────────────────────────────
// Stesso aspetto di _DropCard, ma senza opzione elimina (non è tuo) — al suo
// posto, la possibilità di nasconderlo dal proprio profilo.

class _TaggedDropCard extends ConsumerWidget {
  const _TaggedDropCard({required this.drop, required this.userId});
  final DropModel drop;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropGridTile(
      drop: drop,
      onTap: () => _showDropDetail(context),
      onLongPress: () => _showOptions(context, ref),
    );
  }

  void _showDropDetail(BuildContext context) {
    openDropDetail(context, drop);
  }

  void _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          value: 'hide',
          label: 'Nascondi dal mio profilo',
          icon: Icons.visibility_off_outlined,
        ),
        const AdaptiveAction(
          value: 'report',
          label: 'Segnala post',
          icon: Icons.flag_outlined,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'hide') _hide(context, ref);
    if (action == 'report') _confirmReport(context, ref);
  }

  Future<void> _hide(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(dropRepositoryProvider)
          .setTagHidden(drop.id, hidden: true);
      ref.invalidate(taggedDropsProvider(userId));
      if (context.mounted) {
        EchoToast.show(
          context,
          'Nascosto dal tuo profilo.',
          type: EchoToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  void _confirmReport(BuildContext context, WidgetRef ref) async {
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

// ─── Circle bottom sheet ──────────────────────────────────────────────────────

class _CircleSheet extends ConsumerWidget {
  const _CircleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(myConnectionsProvider);
    final requestsAsync = ref.watch(pendingRequestsProvider);
    final pendingCount = requestsAsync.asData?.value.length ?? 0;

    return EchoBottomSheet(
      height: MediaQuery.of(context).size.height * 0.68,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const SizedBox(height: 8),
            TabBar(
              tabs: [
                const Tab(text: 'Cerchia'),
                Tab(
                  text: pendingCount > 0
                      ? 'Richieste ($pendingCount)'
                      : 'Richieste',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ConnectionsList(
                    asyncProfiles: connectionsAsync,
                    emptyText: 'Nessuna connessione ancora.',
                    onTap: (user) {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfilePage(user: user),
                        ),
                      );
                    },
                  ),
                  _RequestsList(
                    asyncProfiles: requestsAsync,
                    onAccept: (userId) async {
                      await ref
                          .read(connectionRepositoryProvider)
                          .acceptRequest(userId);
                      ref.invalidate(pendingRequestsProvider);
                      ref.invalidate(myConnectionsProvider);
                      ref.invalidate(currentProfileProvider);
                    },
                    onDecline: (userId) async {
                      await ref
                          .read(connectionRepositoryProvider)
                          .removeConnection(userId);
                      ref.invalidate(pendingRequestsProvider);
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}

// ─── Connections list ─────────────────────────────────────────────────────────

class _ConnectionsList extends StatelessWidget {
  const _ConnectionsList({
    required this.asyncProfiles,
    required this.emptyText,
    required this.onTap,
  });

  final AsyncValue<List<ProfileModel>> asyncProfiles;
  final String emptyText;
  final void Function(ProfileModel) onTap;

  @override
  Widget build(BuildContext context) {
    return asyncProfiles.when(
      loading: () => const SkeletonUserList(itemCount: 5),
      error: (_, _) => Center(
        child: Text('Errore', style: AppTextStyles.bodySecondary(context)),
      ),
      data: (users) {
        if (users.isEmpty) {
          return Center(
            child: Text(emptyText, style: AppTextStyles.bodySecondary(context)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          itemBuilder: (_, i) =>
              _UserTile(user: users[i], onTap: () => onTap(users[i])),
        );
      },
    );
  }
}

// ─── Requests list ────────────────────────────────────────────────────────────

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.asyncProfiles,
    required this.onAccept,
    required this.onDecline,
  });

  final AsyncValue<List<ProfileModel>> asyncProfiles;
  final Future<void> Function(String userId) onAccept;
  final Future<void> Function(String userId) onDecline;

  @override
  Widget build(BuildContext context) {
    return asyncProfiles.when(
      loading: () => const SkeletonUserList(itemCount: 3),
      error: (_, _) => Center(
        child: Text('Errore', style: AppTextStyles.bodySecondary(context)),
      ),
      data: (users) {
        if (users.isEmpty) {
          return Center(
            child: Text(
              'Nessuna richiesta in attesa.',
              style: AppTextStyles.bodySecondary(context),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          itemBuilder: (_, i) => _UserTile(
            user: users[i],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionChip(
                  label: 'Accetta',
                  color: AppColors.accent,
                  onTap: () => onAccept(users[i].id),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  label: 'Rifiuta',
                  color: Colors.white24,
                  onTap: () => onDecline(users[i].id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── User tile ────────────────────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, this.onTap, this.trailing});

  final ProfileModel user;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    return ListTile(
      onTap: onTap,
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
      trailing: trailing,
    );
  }
}

// ─── Action chip ──────────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color == AppColors.accent
                ? AppColors.accent
                : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ─── Bell button with badge ───────────────────────────────────────────────────

class _BellButton extends ConsumerWidget {
  const _BellButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
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
