import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/shared/widgets/morphing_panel.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/domain/models/comment_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Apre il pannello dei commenti facendolo crescere ("morph") a partire
/// dall'icona toccata. [context] deve appartenere all'icona stessa (es.
/// avvolta in un [Builder]) così il pannello nasce dal punto giusto.
/// [onCommentCountChanged] viene chiamato con +1 o -1 per aggiornare
/// il contatore nella card chiamante senza ricaricare il feed.
void showCommentsSheet(
  BuildContext context,
  String dropId, {
  required void Function(int delta) onCommentCountChanged,
}) {
  showMorphingPanel(
    context,
    builder: (_) => CommentsSheet(
      dropId: dropId,
      onCommentCountChanged: onCommentCountChanged,
    ),
  );
}

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    super.key,
    required this.dropId,
    required this.onCommentCountChanged,
  });

  final String dropId;
  final void Function(int delta) onCommentCountChanged;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await ref.read(commentsProvider(widget.dropId).notifier).addComment(text);
      _controller.clear();
      widget.onCommentCountChanged(1);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _delete(String commentId) async {
    await ref
        .read(commentsProvider(widget.dropId).notifier)
        .deleteComment(commentId);
    widget.onCommentCountChanged(-1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final commentsAsync = ref.watch(commentsProvider(widget.dropId));
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Text(
                'Commenti',
                style: AppTextStyles.headline(
                  context,
                ).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              commentsAsync.maybeWhen(
                data: (list) => Text(
                  '${list.length}',
                  style: AppTextStyles.bodySecondary(context),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const Spacer(),
              GlassIconButton(
                icon: Icons.close,
                size: 36,
                iconSize: 16,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Comment list — Expanded (not Flexible) so this area always fills
        // the available space regardless of item count, keeping the input
        // bar pinned to the bottom instead of riding up with short lists.
        Expanded(
          child: commentsAsync.when(
            loading: () => const Center(child: SkeletonCommentList()),
            error: (e, _) => Center(
              child: Text(
                'Errore nel caricamento',
                style: AppTextStyles.bodySecondary(context),
              ),
            ),
            data: (comments) => comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.messageSquare,
                          size: 40,
                          color: AppColors.accent.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nessun commento ancora.\nSii il primo!',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySecondary(context),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: comments.length,
                    itemBuilder: (ctx, i) => _CommentTile(
                      comment: comments[i],
                      isOwn: comments[i].userId == currentUserId,
                      isDark: isDark,
                      onDelete: () => _delete(comments[i].id),
                    ),
                  ),
          ),
        ),

        // Input
        Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceLight.withValues(alpha: 0.7)
                        : AppColors.lightBackground,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    style: AppTextStyles.body(context).copyWith(
                      fontSize: 14,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Scrivi un commento…',
                      hintStyle: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSending ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isSending
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.accent,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          LucideIcons.send,
                          size: 16,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Single comment tile ──────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  const _CommentTile({
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
            radius: 18,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: author?.avatarUrl != null
                ? CachedNetworkImageProvider(author!.avatarUrl!)
                : null,
            child: author?.avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
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
                    if (isOwn) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _confirmDelete(context),
                        child: Icon(
                          LucideIcons.trash2,
                          size: 14,
                          color: isDark
                              ? AppColors.textSecondaryLight
                              : AppColors.textSecondaryDark,
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

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina commento',
      message: 'Vuoi eliminare questo commento?',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed == true) onDelete();
  }
}
