import 'dart:io';

import 'package:echo/core/services/connectivity_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/blocked_users_page.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/memory/domain/models/comment_model.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:echo/features/memory/providers/memory_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/features/notifications/presentation/pages/notifications_page.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart' as messaging;
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileAsync = ref.watch(currentProfileProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _Background(isDark: isDark),
          profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Errore: $e', style: AppTextStyles.body(context)),
            ),
            data: (profile) {
              if (profile == null) {
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
        ],
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.userId});

  final ProfileModel profile;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final memoriesAsync = ref.watch(userMemoriesProvider(userId));
    final pendingCount =
        ref.watch(pendingRequestsProvider).asData?.value.length ?? 0;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AvatarWidget(profile: profile),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                profile.displayName.isNotEmpty
                                    ? profile.displayName
                                    : profile.username,
                                maxLines: 1,
                                style: AppTextStyles.headline(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${profile.username}',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${profile.memoriesCount}',
                                      style: AppTextStyles.headline(context),
                                    ),
                                    Text(
                                      'ricordi',
                                      style: AppTextStyles.bodySecondary(context),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 28),
                                GestureDetector(
                                  onTap: () => _showCircleSheet(context, ref),
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${profile.connectionsCount}',
                                            style: AppTextStyles.headline(context),
                                          ),
                                          Text(
                                            'cerchia',
                                            style: AppTextStyles.bodySecondary(
                                                context),
                                          ),
                                        ],
                                      ),
                                      if (pendingCount > 0)
                                        Positioned(
                                          right: -10,
                                          top: -4,
                                          child: Container(
                                            width: 17,
                                            height: 17,
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$pendingCount',
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _BellButton(onTap: () => _showNotifications(context)),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => _showSettings(context, ref),
                      ),
                    ],
                  ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(profile.bio, style: AppTextStyles.body(context)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: isOnline
                          ? () => _showEditProfile(context, ref, profile)
                          : null,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(isOnline ? 'Modifica profilo' : 'Offline'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('I miei ricordi', style: AppTextStyles.headline(context)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        memoriesAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Center(heightFactor: 4, child: CircularProgressIndicator()),
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
                        'Nessun ricordo ancora.\nVai sulla mappa e lascia il primo!',
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    );
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => const NotificationsSheet(),
    );
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

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina account',
      message:
          'Questa azione è permanente e irreversibile.\n\n'
          'Tutti i tuoi ricordi, messaggi e connessioni verranno eliminati definitivamente.',
      confirmLabel: 'Elimina definitivamente',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (!context.mounted) return;
      ref.invalidate(messaging.conversationsProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(myConnectionsProvider);
      ref.invalidate(pendingRequestsProvider);
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, e.toString(), type: EchoToastType.error);
      }
    }
  }

  void _showSettings(BuildContext context, WidgetRef ref) async {
    void goBlocked() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
        );
    Future<void> doLogout() async {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(messaging.conversationsProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(myConnectionsProvider);
      ref.invalidate(pendingRequestsProvider);
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final action = await showCupertinoModalPopup<String>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop('blocked'),
              child: const Text('Utenti bloccati'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop('logout'),
              child: const Text('Esci dall\'account'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(ctx).pop('delete'),
              child: const Text('Elimina account'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
        ),
      );
      if (!context.mounted) return;
      if (action == 'blocked') goBlocked();
      if (action == 'logout') {
        await doLogout();
      } else if (action == 'delete') {
        await _confirmDeleteAccount(context, ref);
      }
      return;
    }

    // Android — Material bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => GlassCard(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Utenti bloccati'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  goBlocked();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Esci dall\'account'),
                onTap: () async {
                  Navigator.pop(context);
                  await doLogout();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Elimina account',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _confirmDeleteAccount(context, ref);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfile(
    BuildContext context,
    WidgetRef ref,
    ProfileModel profile,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => _EditProfileSheet(profile: profile),
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

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return GestureDetector(
      onTap: _uploading ? null : () => _pickAvatar(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: profile.avatarUrl != null
                ? CachedNetworkImageProvider(profile.avatarUrl!)
                : null,
            child: _uploading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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
          if (!_uploading)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26, width: 1.5),
                ),
                child: const Icon(
                    Icons.camera_alt_outlined, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 400,
    );
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(currentProfileProvider.notifier)
          .uploadAvatar(bytes);
      await ref.read(currentProfileProvider.notifier).saveProfile(
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

// ─── Memory card (grid) ───────────────────────────────────────────────────────

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({required this.memory});
  final MemoryModel memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = memory.imageUrl != null;

    return GestureDetector(
      onTap: () => _showMemoryDetail(context, ref),
      onLongPress: () => _showOptions(context, ref),
      child: ClipRRect(
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
            // bottom gradient overlay
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
            // mood dot
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
            // visibility icon
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                memory.visibility.icon,
                size: 11,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            // text overlay
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
                        Icon(
                          Icons.location_on_outlined,
                          size: 10,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            memory.locationName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        timeago.format(memory.createdAt, locale: 'it'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.favorite_border,
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${memory.likesCount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemoryDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => _MemoryDetailSheet(memory: memory),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          value: 'delete',
          label: 'Elimina ricordo',
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
      title: 'Elimina ricordo',
      message: 'Sei sicuro di voler eliminare questo ricordo? L\'azione non è reversibile.',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).deleteMemory(memory.id);
      ref.invalidate(userMemoriesProvider(memory.userId));
      ref.invalidate(discoverProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Ricordo eliminato.', type: EchoToastType.success);
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
      message: 'Sei sicuro di voler segnalare questo contenuto? Lo esamineremo quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).reportMemory(memory.id);
      if (context.mounted) {
        EchoToast.show(context, 'Segnalazione inviata. Grazie.', type: EchoToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }
}

// ─── Mood background ─────────────────────────────────────────────────────────

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

// ─── Memory detail sheet (Instagram-style) ───────────────────────────────────

class _MemoryDetailSheet extends ConsumerStatefulWidget {
  const _MemoryDetailSheet({required this.memory});
  final MemoryModel memory;

  @override
  ConsumerState<_MemoryDetailSheet> createState() => _MemoryDetailSheetState();
}

class _MemoryDetailSheetState extends ConsumerState<_MemoryDetailSheet> {
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _likeLoading = false;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.memory.isLikedByMe;
    _likesCount = widget.memory.likesCount;
    _commentsCount = widget.memory.commentsCount;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;
    if (!ref.read(isOnlineProvider)) {
      EchoToast.show(context, 'Sei offline', type: EchoToastType.info);
      return;
    }
    setState(() => _likeLoading = true);
    try {
      await ref.read(memoryRepositoryProvider).toggleLike(
        widget.memory.id,
        isLiked: _isLiked,
      );
      setState(() {
        _isLiked = !_isLiked;
        _likesCount =
            _isLiked ? _likesCount + 1 : (_likesCount - 1).clamp(0, 9999);
      });
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    if (!ref.read(isOnlineProvider)) {
      EchoToast.show(context, 'Sei offline', type: EchoToastType.info);
      return;
    }
    setState(() => _sendingComment = true);
    try {
      await ref
          .read(commentsProvider(widget.memory.id).notifier)
          .addComment(text);
      _commentCtrl.clear();
      setState(() => _commentsCount++);
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _showPostOptions(BuildContext context, bool isOwn) async {
    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        if (isOwn)
          const AdaptiveAction(
            value: 'delete',
            label: 'Elimina ricordo',
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
    if (!mounted) return;
    if (action == 'delete') _delete();
    if (action == 'report') _report();
  }

  Future<void> _delete() async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina ricordo',
      message: 'Sei sicuro di voler eliminare questo ricordo? L\'azione non è reversibile.',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(memoryRepositoryProvider).deleteMemory(widget.memory.id);
        ref.invalidate(userMemoriesProvider(widget.memory.userId));
        ref.invalidate(discoverProvider);
        if (mounted) {
          Navigator.pop(context);
          EchoToast.show(context, 'Ricordo eliminato.', type: EchoToastType.success);
        }
      } catch (e) {
        if (mounted) {
          EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
        }
      }
    }
  }

  Future<void> _report() async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Segnala post',
      message: 'Sei sicuro di voler segnalare questo contenuto? Lo esamineremo quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).reportMemory(widget.memory.id);
      if (mounted) {
        Navigator.pop(context);
        EchoToast.show(context, 'Segnalazione inviata. Grazie.', type: EchoToastType.success);
      }
    } catch (e) {
      if (mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final memory = widget.memory;
    final commentsAsync = ref.watch(commentsProvider(memory.id));
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.90,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF181528).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header: close + options ("…")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Platform.isIOS
                        ? CupertinoIcons.xmark
                        : Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (buttonContext) => GlassIconButton(
                      icon: Platform.isIOS
                          ? CupertinoIcons.ellipsis
                          : Icons.more_horiz_rounded,
                      onPressed: () => _showPostOptions(
                        buttonContext,
                        currentUserId == memory.userId,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable body
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (memory.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: memory.imageUrl!,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(height: 260, color: Colors.white10),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    )
                  else
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            memory.mood.color.withValues(alpha: 0.35),
                            memory.mood.color.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _MoodChip(mood: memory.mood),
                            const SizedBox(width: 8),
                            Icon(
                              memory.visibility.icon,
                              size: 13,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            const Spacer(),
                            Text(
                              timeago.format(memory.createdAt, locale: 'it'),
                              style: AppTextStyles.bodySecondary(context)
                                  .copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                        if (memory.locationName != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color:
                                    isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  memory.locationName!,
                                  style: AppTextStyles.bodySecondary(context)
                                      .copyWith(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          memory.description,
                          style: AppTextStyles.body(context),
                        ),
                        const SizedBox(height: 16),
                        // Like + comment actions
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _toggleLike,
                              child: Row(
                                children: [
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    child: Icon(
                                      _isLiked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      key: ValueKey(_isLiked),
                                      size: 22,
                                      color: _isLiked
                                          ? const Color(0xFFE8879C)
                                          : (isDark
                                              ? Colors.white54
                                              : Colors.black38),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_likesCount',
                                    style: AppTextStyles.body(context)
                                        .copyWith(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black38,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_commentsCount',
                                  style: AppTextStyles.body(context)
                                      .copyWith(fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(
                          color:
                              isDark ? Colors.white12 : Colors.black12,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Commenti',
                          style: AppTextStyles.headline(context)
                              .copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  // Inline comments
                  commentsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (comments) => comments.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            child: Text(
                              'Nessun commento ancora. Sii il primo!',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          )
                        : Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                for (final c in comments)
                                  _CommentRow(
                                    comment: c,
                                    isOwn: c.userId == currentUserId,
                                    isDark: isDark,
                                    onDelete: () async {
                                      await ref
                                          .read(commentsProvider(memory.id)
                                              .notifier)
                                          .deleteComment(c.id);
                                      setState(() => _commentsCount =
                                          (_commentsCount - 1)
                                              .clamp(0, 9999));
                                    },
                                  ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            // Pinned comment input
            Divider(
              height: 1,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      enabled: isOnline,
                      textCapitalization: TextCapitalization.sentences,
                      style:
                          AppTextStyles.body(context).copyWith(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Scrivi un commento…',
                        hintStyle: AppTextStyles.bodySecondary(context)
                            .copyWith(fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (_sendingComment || !isOnline) ? null : _sendComment,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _sendingComment
                            ? AppColors.accent.withValues(alpha: 0.5)
                            : AppColors.accent,
                      ),
                      child: _sendingComment
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
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

// ─── Comment row (inline in detail sheet) ─────────────────────────────────────

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.isOwn,
    required this.isDark,
    required this.onDelete,
  });

  final CommentModel comment;
  final bool isOwn;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    final name = author != null
        ? (author.displayName.isNotEmpty ? author.displayName : author.username)
        : 'Utente';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: author?.avatarUrl != null
                ? CachedNetworkImageProvider(author!.avatarUrl!)
                : null,
            child: author?.avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeago.format(comment.createdAt, locale: 'it'),
                      style: AppTextStyles.bodySecondary(context)
                          .copyWith(fontSize: 11),
                    ),
                    if (isOwn) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: onDelete,
                        child: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: AppTextStyles.body(context).copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mood chip (detail sheet) ─────────────────────────────────────────────────

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.mood});
  final MemoryMood mood;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mood.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mood.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${mood.emoji} ${mood.label}',
        style: TextStyle(
          fontSize: 12,
          color: mood.color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Edit profile sheet ───────────────────────────────────────────────────────

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final ProfileModel profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameCtrl = TextEditingController(
    text: widget.profile.displayName,
  );
  late final _bioCtrl = TextEditingController(text: widget.profile.bio);
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(currentProfileProvider.notifier).saveProfile(
            displayName: _nameCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassCard(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Modifica profilo',
                      style: AppTextStyles.headline(context),
                    ),
                    const Spacer(),
                    GlassIconButton(
                      icon: Icons.close,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bioCtrl,
                  maxLines: 3,
                  maxLength: 150,
                  decoration: InputDecoration(
                    labelText: 'Bio',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.accent
                                          .withValues(alpha: 0.4),
                                      shape: const StadiumBorder(),
                                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salva'),
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

// ─── Circle bottom sheet ──────────────────────────────────────────────────────

class _CircleSheet extends ConsumerWidget {
  const _CircleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connectionsAsync = ref.watch(myConnectionsProvider);
    final requestsAsync = ref.watch(pendingRequestsProvider);
    final pendingCount = requestsAsync.asData?.value.length ?? 0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.68,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181528) : const Color(0xFFF3F1FC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
          itemBuilder: (_, i) => _UserTile(
            user: users[i],
            onTap: () => onTap(users[i]),
          ),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
    final name =
        user.displayName.isNotEmpty ? user.displayName : user.username;
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color == AppColors.accent ? AppColors.accent : Colors.white54,
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
