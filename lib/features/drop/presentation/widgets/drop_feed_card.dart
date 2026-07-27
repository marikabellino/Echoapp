import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/presentation/widgets/comments_sheet.dart';
import 'package:echo/features/drop/presentation/widgets/likers_sheet.dart';
import 'package:echo/features/drop/presentation/widgets/tag_people_sheet.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

// ─── Big "Instagram-style" drop card, used in Scopri and negli eventi ────────

class DropCard extends ConsumerWidget {
  const DropCard({
    super.key,
    required this.drop,
    required this.onLike,
    required this.onCommentCountChanged,
    required this.onTap,
    required this.onAuthorTap,
  });

  final DropModel drop;
  final VoidCallback onLike;
  final void Function(int delta) onCommentCountChanged;
  final VoidCallback onTap;
  final void Function(ProfileModel) onAuthorTap;

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final currentUserId = ref.read(currentUserProvider)?.id ?? '';
    final isOwn = currentUserId == drop.userId;

    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        if (isOwn)
          const AdaptiveAction(
            value: 'tag',
            label: 'Tagga persone',
            icon: Icons.person_add_alt_1_outlined,
          ),
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
    if (action == null || !context.mounted) return;
    if (action == 'tag') _openTagPicker(context, ref);
    if (action == 'delete') _confirmDelete(context, ref);
    if (action == 'report') _confirmReport(context, ref);
  }

  // Tag "in aggiunta", non un editor completo: la RPC tag_users_on_drop può
  // solo inserire (on conflict do nothing), non ha modo di rimuovere un tag
  // esistente — per questo lo sheet esclude chi è già taggato invece di
  // pre-selezionarlo, così non lascia intendere che deselezionarlo lo tolga.
  Future<void> _openTagPicker(BuildContext context, WidgetRef ref) async {
    final existingTags = await ref.read(dropTagsProvider(drop.id).future);
    if (!context.mounted) return;

    final result = await showModalBottomSheet<List<ProfileModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => TagPeopleSheet(
        excludeUserIds: existingTags.map((u) => u.id).toSet(),
      ),
    );
    if (result == null || result.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(dropRepositoryProvider)
          .tagUsersOnDrop(drop.id, result.map((u) => u.id).toList());
      ref.invalidate(dropTagsProvider(drop.id));
      if (context.mounted) {
        EchoToast.show(context, 'Persone taggate.', type: EchoToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
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
      ref.invalidate(discoverProvider);
      ref.invalidate(userDropsProvider(drop.userId));
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = drop.imageUrl != null;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background: photo or mood-tinted gradient ────────────
              if (hasImage)
                CachedNetworkImage(
                  imageUrl: drop.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.white10),
                  errorWidget: (_, _, _) =>
                      MoodGradientBackground(mood: drop.mood),
                )
              else
                MoodGradientBackground(mood: drop.mood),

              // ── Top scrim: author + options ──────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (drop.author != null)
                        Expanded(
                          child: _AuthorWithTags(
                            author: drop.author!,
                            dropId: drop.id,
                            onTap: () => onAuthorTap(drop.author!),
                          ),
                        ),
                      Builder(
                        builder: (buttonContext) => GestureDetector(
                          onTap: () => _showOptions(buttonContext, ref),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom scrim: mood, caption, stats ───────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 44, 14, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MoodBadge(mood: drop.mood, overlay: true),
                      const SizedBox(height: 8),
                      _ExpandableDescription(
                        text: drop.description,
                        style: AppTextStyles.body(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (drop.locationName != null) ...[
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                drop.locationName!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            timeago.format(drop.createdAt, locale: 'it'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          Builder(
                            builder: (iconContext) => CircleAction(
                              icon: Icons.chat_bubble_outline_rounded,
                              iconColor: Colors.white,
                              count: drop.commentsCount,
                              onTap: () => showCommentsSheet(
                                iconContext,
                                drop.id,
                                onCommentCountChanged: onCommentCountChanged,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          CircleAction(
                            icon: drop.isLikedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            iconColor: drop.isLikedByMe
                                ? const Color(0xFFE8879C)
                                : Colors.white,
                            count: drop.likesCount,
                            onTap: onLike,
                          ),
                        ],
                      ),
                      if (drop.likesCount > 0) ...[
                        const SizedBox(height: 4),
                        _LikedByLine(dropId: drop.id),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── "Piace a" ──────────────────────────────────────────────────────────────

class _LikedByLine extends ConsumerWidget {
  const _LikedByLine({required this.dropId});
  final String dropId;

  static String _truncate(String s, [int maxLen = 16]) =>
      s.length > maxLen ? '${s.substring(0, maxLen)}…' : s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likers = ref.watch(likersProvider(dropId)).asData?.value ?? const [];
    if (likers.isEmpty) return const SizedBox.shrink();

    final first = _truncate(likers.first.username);
    final label = likers.length == 1
        ? 'Piace a @$first'
        : 'Piace a @$first e altri ${likers.length - 1}';

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LikersSheet(dropId: dropId),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
      ),
    );
  }
}

// ─── Descrizione con "Leggi tutto" ────────────────────────────────────────────

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ExpandableDescription> createState() =>
      _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  static const _collapsedLines = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: _collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'Mostra meno' : 'Leggi tutto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Mood badge ───────────────────────────────────────────────────────────────

class MoodBadge extends StatelessWidget {
  const MoodBadge({super.key, required this.mood, this.overlay = false});
  final DropMood mood;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: overlay
            ? Colors.white.withValues(alpha: 0.16)
            : mood.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: overlay
              ? mood.color.withValues(alpha: 0.7)
              : mood.color.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        mood.label,
        style: TextStyle(
          fontSize: 12,
          color: overlay ? Colors.white : mood.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Author + "è con" tag ──────────────────────────────────────────────────────

class _AuthorWithTags extends ConsumerWidget {
  const _AuthorWithTags({
    required this.author,
    required this.dropId,
    required this.onTap,
  });

  final ProfileModel author;
  final String dropId;
  final VoidCallback onTap;

  // Tronca per numero di caratteri, non per pixel disponibili: due Flexible
  // a pari peso in un Row dividono sempre lo spazio a metà anche quando uno
  // dei due nomi sarebbe corto, tagliando entrambi senza motivo. Così invece
  // restano leggibili e di lunghezza prevedibile qualunque sia la larghezza
  // della card.
  static String _truncate(String s, [int maxLen = 14]) =>
      s.length > maxLen ? '${s.substring(0, maxLen)}…' : s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(dropTagsProvider(dropId)).asData?.value ?? const [];
    final name = author.displayName.isNotEmpty
        ? author.displayName
        : author.username;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.accent.withValues(alpha: 0.2),
            backgroundImage: author.avatarUrl != null
                ? CachedNetworkImageProvider(author.avatarUrl!)
                : null,
            child: author.avatarUrl == null
                ? Text(
                    name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          // Flexible qui è solo una rete di sicurezza: il contenuto è già
          // corto per via del taglio a caratteri sopra, quindi normalmente
          // non deve stringere nulla — scatta solo nei rari casi in cui
          // anche il testo già tagliato non ci starebbe, evitando l'overflow.
          Flexible(
            child: Text(
              '@${_truncate(author.username)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const Text(
              '  è con ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
            Flexible(
              child: Text(
                '@${_truncate(tags.first.username)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            if (tags.length > 1)
              Text(
                ' +${tags.length - 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Circle action (like / comment icon-only badge) ───────────────────────────

class CircleAction extends StatelessWidget {
  const CircleAction({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  // Se presente (e > 0), icona e numero si stringono dentro lo stesso
  // pallino invece che uno accanto all'altro — il cerchio resta 42x42.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final showCount = count != null && count! > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 0.75,
          ),
        ),
        child: showCount
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: iconColor),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: iconColor,
                    ),
                  ),
                ],
              )
            : Icon(icon, size: 19, color: iconColor),
      ),
    );
  }
}

// ─── Mood gradient fallback (text-only drops) ─────────────────────────────────

class MoodGradientBackground extends StatelessWidget {
  const MoodGradientBackground({super.key, required this.mood});
  final DropMood mood;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            mood.color.withValues(alpha: 0.85),
            mood.color.withValues(alpha: 0.45),
          ],
        ),
      ),
    );
  }
}
