import 'package:echo/features/drop/presentation/widgets/relation_badge.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/drop/domain/models/comment_model.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

// ─── Drop detail sheet (Instagram-style) ───────────────────────────────────

String dropHeroTag(DropModel drop) => 'drop-image-${drop.id}';

Future<void> openDropDetail(BuildContext context, DropModel drop) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => DropDetailPage(drop: drop),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

Future<void> confirmReportComment(
  BuildContext context,
  String commentId,
) async {
  final confirmed = await showAdaptiveConfirmDialog(
    context: context,
    title: 'Segnala commento',
    message:
        'Lo esamineremo entro 24 ore. Chi l\'ha scritto non saprà che sei stato tu.',
    confirmLabel: 'Segnala',
    cancelLabel: 'Annulla',
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(dropRepositoryProvider).reportComment(commentId);
    if (context.mounted) {
      EchoToast.show(
        context,
        'Segnalazione inviata. Grazie.',
        type: EchoToastType.success,
      );
    }
  } catch (_) {
    if (context.mounted) {
      EchoToast.show(
        context,
        'Segnalazione non riuscita',
        type: EchoToastType.error,
      );
    }
  }
}

class DropDetailPage extends ConsumerStatefulWidget {
  const DropDetailPage({super.key, required this.drop});
  final DropModel drop;

  @override
  ConsumerState<DropDetailPage> createState() => _DropDetailPageState();
}

class _DropDetailPageState extends ConsumerState<DropDetailPage> {
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _likeLoading = false;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;

  int _heartBurst = 0;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.drop.isLikedByMe;
    _likesCount = widget.drop.likesCount;
    _commentsCount = widget.drop.commentsCount;
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
      await ref
          .read(dropRepositoryProvider)
          .toggleLike(widget.drop.id, isLiked: _isLiked);
      setState(() {
        _isLiked = !_isLiked;
        _likesCount = _isLiked
            ? _likesCount + 1
            : (_likesCount - 1).clamp(0, 9999);
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
          .read(commentsProvider(widget.drop.id).notifier)
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
    if (!mounted) return;
    if (action == 'delete') _delete();
    if (action == 'report') _report();
  }

  Future<void> _delete() async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina drop',
      message:
          'Sei sicuro di voler eliminare questo drop? L\'azione non è reversibile.',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed == true && mounted) {
      try {
        await ref
            .read(dropRepositoryProvider)
            .deleteDrop(widget.drop.id, imageUrl: widget.drop.imageUrl);
        ref.invalidate(userDropsProvider(widget.drop.userId));
        ref.invalidate(discoverProvider);
        if (mounted) {
          Navigator.pop(context);
          EchoToast.show(
            context,
            'Drop eliminato.',
            type: EchoToastType.success,
          );
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
      message:
          'Sei sicuro di voler segnalare questo contenuto? Lo esamineremo quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(dropRepositoryProvider).reportDrop(widget.drop.id);
      if (mounted) {
        Navigator.pop(context);
        EchoToast.show(
          context,
          'Segnalazione inviata. Grazie.',
          type: EchoToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    setState(() => _heartBurst++);
    if (!_isLiked) _toggleLike();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    final drop = widget.drop;
    final commentsAsync = ref.watch(commentsProvider(drop.id));
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    final size = MediaQuery.sizeOf(context);
    final author = drop.author;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: GestureDetector(
                  onDoubleTap: _onDoubleTap,
                  child: SizedBox(
                    height: drop.imageUrl != null
                        ? size.width * 1.25
                        : topInset + 180,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: dropHeroTag(drop),
                          child: drop.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: drop.imageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => const ColoredBox(
                                    color: AppColors.darkSurfaceLight,
                                  ),
                                  errorWidget: (_, _, _) =>
                                      const DropPlaceholder(),
                                )
                              : const DropPlaceholder(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 0.18, 0.7, 1.0],
                              colors: [
                                Color(0x99000000),
                                Color(0x00000000),
                                Color(0x00000000),
                                AppColors.darkBackground,
                              ],
                            ),
                          ),
                        ),
                        if (_heartBurst > 0)
                          Center(
                            child:
                                LikeBurst(key: ValueKey(_heartBurst), size: 140),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (author != null) ...[
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.darkSurfaceLight,
                              backgroundImage: author.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      author.avatarUrl!,
                                    )
                                  : null,
                              child: author.avatarUrl == null
                                  ? Text(
                                      author.username.characters.first
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '@${author.username}',
                                style: AppTextStyles.body(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              timeago.format(drop.createdAt, locale: 'it'),
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (drop.description.isNotEmpty)
                        Text(
                          drop.description,
                          style: AppTextStyles.body(
                            context,
                          ).copyWith(fontSize: 18, height: 1.35),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          RelationBadge(drop: drop),
                          if (drop.displayLocation != null)
                            _InfoChip(
                              icon: Icons.place_outlined,
                              label: drop.displayLocation!,
                            ),
                          if (drop.eventTitle != null)
                            _InfoChip(
                              icon: Icons.event_rounded,
                              label: drop.eventTitle!,
                              color: AppColors.accentSecondary,
                            ),
                          _InfoChip(
                            icon: drop.visibility.icon,
                            label: switch (drop.visibility) {
                              DropVisibility.public => 'Pubblico',
                              DropVisibility.circle => 'Cerchia',
                              DropVisibility.private => 'Privato',
                            },
                          ),
                          if (author == null)
                            _InfoChip(
                              icon: Icons.schedule_rounded,
                              label: timeago.format(
                                drop.createdAt,
                                locale: 'it',
                              ),
                            ),
                        ],
                      ),
                      _TaggedPeopleRow(dropId: drop.id),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _ActionPill(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _toggleLike();
                            },
                            active: _isLiked,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                      _isLiked
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      key: ValueKey(_isLiked),
                                      size: 20,
                                      color: _isLiked
                                          ? AppColors.accent
                                          : Colors.white,
                                    )
                                    .animate(key: ValueKey(_isLiked))
                                    .scale(
                                      begin: const Offset(0.6, 0.6),
                                      duration: 280.ms,
                                      curve: Curves.easeOutBack,
                                    ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_likesCount',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionPill(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 19,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_commentsCount',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Commenti',
                        style: AppTextStyles.headline(
                          context,
                        ).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: commentsAsync.when(
                  loading: () => const SkeletonCommentList(itemCount: 2),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (comments) => comments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Text(
                            'Nessun commento ancora. Sii il primo!',
                            style: AppTextStyles.bodySecondary(context),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              for (final c in comments)
                                _CommentRow(
                                  comment: c,
                                  isOwn: c.userId == currentUserId,
                                  isDark: true,
                                  onDelete: () async {
                                    await ref
                                        .read(
                                          commentsProvider(drop.id).notifier,
                                        )
                                        .deleteComment(c.id);
                                    setState(
                                      () => _commentsCount =
                                          (_commentsCount - 1).clamp(0, 9999),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 96 + safeBottom)),
            ],
          ),
          Positioned(
            top: topInset + 4,
            left: 8,
            right: 8,
            child: Row(
              children: [
                GlassIconButton(
                  icon: Platform.isIOS
                      ? CupertinoIcons.chevron_down
                      : Icons.keyboard_arrow_down_rounded,
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
                      currentUserId == drop.userId,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    10 + (bottomInset > 0 ? bottomInset : safeBottom),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.darkBackground.withValues(alpha: 0.75),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: TextField(
                            controller: _commentCtrl,
                            enabled: isOnline,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppTextStyles.body(
                              context,
                            ).copyWith(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Scrivi un commento…',
                              hintStyle: AppTextStyles.bodySecondary(
                                context,
                              ).copyWith(fontSize: 14),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (_) => _sendComment(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: (_sendingComment || !isOnline)
                            ? null
                            : _sendComment,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _sendingComment
                                ? AppColors.accent.withValues(alpha: 0.5)
                                : AppColors.accent,
                          ),
                          child: _sendingComment
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: MingleDotsLoader(size: 16, color: Colors.white),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                        ),
                      ),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.child, this.onTap, this.active = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active
                ? AppColors.accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: child,
      ),
    );
  }
}

// ─── Tagged people row (detail sheet) ─────────────────────────────────────────

class _TaggedPeopleRow extends ConsumerWidget {
  const _TaggedPeopleRow({required this.dropId});
  final String dropId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(dropTagsProvider(dropId));
    final tags = tagsAsync.asData?.value ?? const [];
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Con ', style: AppTextStyles.bodySecondary(context)),
          for (final (i, user) in tags.indexed)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UserProfilePage(user: user)),
              ),
              child: Text(
                i < tags.length - 1
                    ? '@${user.username}, '
                    : '@${user.username}',
                style: AppTextStyles.bodySecondary(context).copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
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
                      style: AppTextStyles.body(
                        context,
                      ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeago.format(comment.createdAt, locale: 'it'),
                      style: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(fontSize: 11),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isOwn
                          ? onDelete
                          : () => confirmReportComment(context, comment.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isOwn ? Icons.delete_outline : Icons.flag_outlined,
                          size: 15,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ),
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
