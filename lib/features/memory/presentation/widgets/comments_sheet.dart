import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/memory/domain/models/comment_model.dart';
import 'package:echo/features/memory/providers/memory_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Apre il bottom sheet dei commenti per un ricordo.
/// [onCommentCountChanged] viene chiamato con +1 o -1 per aggiornare
/// il contatore nella card chiamante senza ricaricare il feed.
void showCommentsSheet(
  BuildContext context,
  String memoryId, {
  required void Function(int delta) onCommentCountChanged,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentsSheet(
      memoryId: memoryId,
      onCommentCountChanged: onCommentCountChanged,
    ),
  );
}

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    super.key,
    required this.memoryId,
    required this.onCommentCountChanged,
  });

  final String memoryId;
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
      await ref.read(commentsProvider(widget.memoryId).notifier).addComment(text);
      _controller.clear();
      widget.onCommentCountChanged(1);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _delete(String commentId) async {
    await ref
        .read(commentsProvider(widget.memoryId).notifier)
        .deleteComment(commentId);
    widget.onCommentCountChanged(-1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final commentsAsync = ref.watch(commentsProvider(widget.memoryId));
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.92)
                : AppColors.lightSurface.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 14),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Commenti',
                      style: AppTextStyles.headline(context).copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
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
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        LucideIcons.x,
                        size: 20,
                        color: isDark
                            ? AppColors.textSecondaryLight
                            : AppColors.textSecondaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),

              // Comment list
              Flexible(
                child: commentsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'Errore nel caricamento',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ),
                  data: (comments) => comments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
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
                          shrinkWrap: true,
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
                            color: isDark
                                ? AppColors.textLight
                                : AppColors.textDark,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Scrivi un commento…',
                            hintStyle:
                                AppTextStyles.bodySecondary(context).copyWith(
                              fontSize: 14,
                            ),
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
          ),
        ),
      ),
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
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeago.format(comment.createdAt, locale: 'it'),
                      style: AppTextStyles.bodySecondary(context).copyWith(
                        fontSize: 11,
                      ),
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

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina commento'),
        content: const Text('Vuoi eliminare questo commento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
            child: const Text(
              'Elimina',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
