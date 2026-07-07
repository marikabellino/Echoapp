import 'dart:async';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/messaging/data/gif_search_service.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/domain/models/message_model.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:echo/shared/widgets/skeleton_loader.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversation});

  final ConversationModel conversation;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Timer? _typingDebounce;

  // Con la lista in reverse:true, pixels=0 è il fondo (più recente): ci si
  // parte già "vicino al fondo", niente scroll iniziale da forzare.
  bool _isNearBottom = true;
  int _newMessagesWhileAway = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // Vicini alla cima (più vecchi) della cronologia già caricata: carica la
    // pagina precedente.
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref
          .read(
            chatProvider((
              widget.conversation.id,
              widget.conversation.otherUserId,
            )).notifier,
          )
          .loadMore();
    }

    final nearBottom = pos.pixels <= 80;
    if (nearBottom != _isNearBottom) {
      setState(() {
        _isNearBottom = nearBottom;
        if (nearBottom) _newMessagesWhileAway = 0;
      });
    }
  }

  void _onTextChanged() {
    if (_controller.text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 300), () {
      ref
          .read(
            chatProvider((
              widget.conversation.id,
              widget.conversation.otherUserId,
            )).notifier,
          )
          .notifyTyping();
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // reverse:true → 0 è il fondo/più recente (non maxScrollExtent).
  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
    setState(() => _newMessagesWhileAway = 0);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final status = ref
        .read(connectionStatusProvider(widget.conversation.otherUserId))
        .asData
        ?.value;
    if (status == ConnectionStatus.blocked ||
        status == ConnectionStatus.blockedByThem) {
      return;
    }
    _controller.clear();
    await ref
        .read(
          chatProvider((
            widget.conversation.id,
            widget.conversation.otherUserId,
          )).notifier,
        )
        .sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _openGifPicker() async {
    final status = ref
        .read(connectionStatusProvider(widget.conversation.otherUserId))
        .asData
        ?.value;
    if (status == ConnectionStatus.blocked ||
        status == ConnectionStatus.blockedByThem) {
      return;
    }
    _focusNode.unfocus();
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => const _GifPickerSheet(),
    );
    if (gifUrl == null || !mounted) return;
    await ref
        .read(
          chatProvider((
            widget.conversation.id,
            widget.conversation.otherUserId,
          )).notifier,
        )
        .sendGif(gifUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = ref.watch(
      chatProvider((widget.conversation.id, widget.conversation.otherUserId)),
    );
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';

    // Scrolla in fondo solo per messaggi davvero nuovi (inviati o ricevuti in
    // coda) — non quando la crescita della lista è dovuta a loadMore() che
    // aggiunge cronologia più vecchia in testa (stesso ultimo messaggio).
    // Se non si è vicini al fondo (si sta leggendo la cronologia sopra), non
    // si forza lo scroll: si mostra invece il pulsante "nuovi messaggi".
    ref.listen(
      chatProvider((widget.conversation.id, widget.conversation.otherUserId)),
      (prev, next) {
        final prevMessages = prev?.messages ?? const [];
        if (next.messages.length <= prevMessages.length) return;
        final prevLastId = prevMessages.isNotEmpty
            ? prevMessages.last.id
            : null;
        final nextLast = next.messages.last;
        if (prevLastId == nextLast.id) return;

        final isMine = nextLast.senderId == currentUserId;
        if (isMine || _isNearBottom) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        } else if (mounted) {
          setState(() => _newMessagesWhileAway++);
        }
      },
    );

    final conv = widget.conversation;
    final blockStatus = ref
        .watch(connectionStatusProvider(conv.otherUserId))
        .asData
        ?.value;
    final isBlocked =
        blockStatus == ConnectionStatus.blocked ||
        blockStatus == ConnectionStatus.blockedByThem;

    final body = Column(
      children: [
        _ChatAppBar(conversation: conv, isDark: isDark),
        Expanded(
          child: Stack(
            children: [
              if (chatState.isLoading)
                const SkeletonChatMessages()
              else if (chatState.messages.isEmpty)
                Center(
                  child: Text(
                    'Nessun messaggio.\nDi\' ciao!',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary(context),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    // newest→oldest: con reverse:true l'indice 0 è il fondo
                    // (il più recente), così si può inserire in testa alla
                    // lista senza far saltare la posizione di scroll.
                    final reversed = chatState.messages.reversed.toList();
                    final typingOffset = chatState.isOtherTyping ? 1 : 0;
                    final itemCount =
                        reversed.length +
                        typingOffset +
                        (chatState.isLoadingMore ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: itemCount,
                      itemBuilder: (ctx, i) {
                        if (chatState.isOtherTyping && i == 0) {
                          return const _TypingIndicator();
                        }
                        final msgIndex = i - typingOffset;
                        if (msgIndex >= reversed.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final msg = reversed[msgIndex];
                        final isMine = msg.senderId == currentUserId;
                        final isOptimistic = msg.id.startsWith('tmp_');
                        final isOldest = msgIndex == reversed.length - 1;
                        final showTime =
                            isOldest ||
                            msg.createdAt
                                    .difference(
                                      reversed[msgIndex + 1].createdAt,
                                    )
                                    .inMinutes
                                    .abs() >
                                10;
                        return _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          isOptimistic: isOptimistic,
                          showTime: showTime,
                          isDark: isDark,
                        );
                      },
                    );
                  },
                ),
              if (!_isNearBottom && chatState.messages.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: _JumpToBottomButton(
                    newCount: _newMessagesWhileAway,
                    onTap: _scrollToBottom,
                  ),
                ),
            ],
          ),
        ),
        if (isBlocked)
          _BlockedInputNotice(
            isDark: isDark,
            otherUserId: conv.otherUserId,
            iBlockedThem: blockStatus == ConnectionStatus.blocked,
          )
        else
          _InputBar(
            controller: _controller,
            focusNode: _focusNode,
            isDark: isDark,
            isSending: chatState.isSending,
            onSend: _send,
            onGifTap: _openGifPicker,
          ),
      ],
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? null : Colors.white,
      body: isDark ? AnimatedGradientBackground(child: body) : body,
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────

class _ChatAppBar extends ConsumerWidget {
  const _ChatAppBar({required this.conversation, required this.isDark});

  final ConversationModel conversation;
  final bool isDark;

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final isBlocked =
        ref
            .read(connectionStatusProvider(conversation.otherUserId))
            .asData
            ?.value ==
        ConnectionStatus.blocked;

    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          value: 'report',
          label: 'Segnala utente',
          icon: Icons.flag_outlined,
        ),
        AdaptiveAction(
          value: isBlocked ? 'unblock' : 'block',
          label: isBlocked ? 'Sblocca utente' : 'Blocca utente',
          icon: isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
          isDestructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'report':
        _confirmReport(context, ref);
      case 'block':
        _confirmBlock(context, ref);
      case 'unblock':
        _unblock(context, ref);
    }
  }

  Future<void> _confirmReport(BuildContext context, WidgetRef ref) async {
    final name = conversation.otherName;
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Segnala utente',
      message:
          'Vuoi segnalare $name? Esamineremo la segnalazione quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(connectionRepositoryProvider)
          .reportUser(conversation.otherUserId);
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

  Future<void> _confirmBlock(BuildContext context, WidgetRef ref) async {
    final name = conversation.otherName;
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Blocca utente',
      message: 'Vuoi bloccare $name? Non potrà più scriverti né trovarti.',
      confirmLabel: 'Blocca',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(connectionRepositoryProvider)
          .blockUser(conversation.otherUserId);
      ref.invalidate(connectionStatusProvider(conversation.otherUserId));
      ref.invalidate(conversationsProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Utente bloccato', type: EchoToastType.info);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(connectionRepositoryProvider)
          .unblockUser(conversation.otherUserId);
      ref.invalidate(connectionStatusProvider(conversation.otherUserId));
      ref.invalidate(conversationsProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Utente sbloccato', type: EchoToastType.info);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                SizedBox(width: 20),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage: conversation.otherAvatarUrl != null
                      ? CachedNetworkImageProvider(conversation.otherAvatarUrl!)
                      : null,
                  child: conversation.otherAvatarUrl == null
                      ? Text(
                          conversation.otherName.isNotEmpty
                              ? conversation.otherName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    conversation.otherName,
                    style: AppTextStyles.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700, fontSize: 17),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Builder(
                  builder: (buttonContext) => GlassIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'Altre opzioni',
                    onPressed: () => _showOptions(buttonContext, ref),
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

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isOptimistic,
    required this.showTime,
    required this.isDark,
  });

  final MessageModel message;
  final bool isMine;
  final bool isOptimistic;
  final bool showTime;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              timeago.format(message.createdAt, locale: 'it'),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary(
                context,
              ).copyWith(fontSize: 11),
            ),
          ),
        Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Container(
              margin: EdgeInsets.only(
                bottom: 4,
                left: isMine ? 48 : 0,
                right: isMine ? 0 : 48,
              ),
              child: message.isGif ? _buildGif(context) : _buildText(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildText(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? AppColors.accent
            : (isDark ? AppColors.darkSurfaceLight : AppColors.lightSurface),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(isMine ? AppRadius.md : 4),
          bottomRight: Radius.circular(isMine ? 4 : AppRadius.md),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              message.content,
              style: AppTextStyles.body(context).copyWith(
                color: isMine
                    ? Colors.white
                    : (isDark ? AppColors.textLight : AppColors.textDark),
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ReadReceipt(isMine: isMine, isOptimistic: isOptimistic, message: message, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildGif(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CachedNetworkImage(
            imageUrl: message.gifUrl!,
            width: 180,
            height: 135,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              width: 180,
              height: 135,
              color: isDark
                  ? AppColors.darkSurfaceLight
                  : AppColors.lightSurface,
            ),
            errorWidget: (_, _, _) => Container(
              width: 180,
              height: 135,
              color: isDark
                  ? AppColors.darkSurfaceLight
                  : AppColors.lightSurface,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: isOptimistic
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isMine && message.isRead
                          ? LucideIcons.checkCheck
                          : LucideIcons.check,
                      size: 11,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Read receipt (spunta singola/doppia o spinner d'invio) ──────────────────

class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt({
    required this.isMine,
    required this.isOptimistic,
    required this.message,
    required this.isDark,
  });

  final bool isMine;
  final bool isOptimistic;
  final MessageModel message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: isOptimistic
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            )
          : Icon(
              isMine && message.isRead
                  ? LucideIcons.checkCheck
                  : LucideIcons.check,
              size: 12,
              color: isMine
                  ? Colors.white
                  : (isDark
                        ? AppColors.textSecondaryLight
                        : AppColors.textSecondaryDark),
            ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isSending,
    required this.onSend,
    required this.onGifTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onGifTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.55)
                  : AppColors.lightSurface.withValues(alpha: 0.85),
            ),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.gif_box_outlined,
                  size: 42,
                  iconSize: 22,
                  tooltip: 'Invia una GIF',
                  onPressed: onGifTap,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceLight.withValues(alpha: 0.7)
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(
                        color: isDark
                            ? Theme.of(context).dividerColor
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textDark,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Scrivi un messaggio…',
                        hintStyle: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: isSending ? null : onSend,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSending
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.accent,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      LucideIcons.send,
                      size: 18,
                      color: Colors.white,
                    ),
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

// ─── Blocked notice ───────────────────────────────────────────────────────────

class _BlockedInputNotice extends ConsumerWidget {
  const _BlockedInputNotice({
    required this.isDark,
    required this.otherUserId,
    required this.iBlockedThem,
  });

  final bool isDark;
  final String otherUserId;
  final bool iBlockedThem;

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(connectionRepositoryProvider).unblockUser(otherUserId);
      ref.invalidate(connectionStatusProvider(otherUserId));
      ref.invalidate(conversationsProvider);
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.55)
                  : AppColors.lightSurface.withValues(alpha: 0.85),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                Text(
                  'Non puoi inviare messaggi a questo utente.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySecondary(context),
                ),
                if (iBlockedThem) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _unblock(context, ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        color: AppColors.accent.withValues(alpha: 0.12),
                        border: Border.all(color: AppColors.accent),
                      ),
                      child: const Text(
                        'Sblocca utente',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Jump to bottom (liquid glass + badge nuovi messaggi) ────────────────────

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.newCount, required this.onTap});

  final int newCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          icon: Icons.arrow_downward_rounded,
          size: 44,
          iconSize: 20,
          onPressed: onTap,
        ),
        if (newCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
              child: Text(
                newCount > 99 ? '99+' : '$newCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── GIF picker sheet (ricerca Klipy) ─────────────────────────────────────────

class _GifPickerSheet extends ConsumerStatefulWidget {
  const _GifPickerSheet();

  @override
  ConsumerState<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends ConsumerState<_GifPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<GifResult> _results = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load(() => ref.read(gifSearchServiceProvider).trending());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(Future<List<GifResult>> Function() fetch) async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await fetch();
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _load(
        () => query.isEmpty
            ? ref.read(gifSearchServiceProvider).trending()
            : ref.read(gifSearchServiceProvider).search(query),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return EchoBottomSheet(
      height: MediaQuery.of(context).size.height * 0.75,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GlassIconButton(
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: AppTextStyles.body(context),
                decoration: InputDecoration(
                  hintText: 'Cerca una GIF',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error
                  ? Center(
                      child: Text(
                        'Impossibile caricare le GIF.',
                        style: AppTextStyles.bodySecondary(context),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        'Nessuna GIF trovata.',
                        style: AppTextStyles.bodySecondary(context),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.4,
                          ),
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final gif = _results[i];
                        return GestureDetector(
                          onTap: () =>
                              Navigator.of(context).pop(gif.fullUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: CachedNetworkImage(
                              imageUrl: gif.previewUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                color: AppColors.accent.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.accent.withValues(
                                  alpha: 0.08,
                                ),
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
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

// ─── Typing indicator (3 pallini animati) ────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _dots;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _dots = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      ),
    );
    _anims = _dots
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: -6,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) {
          _dots[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _dots) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceLight : AppColors.lightSurface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.md),
            topRight: Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(AppRadius.md),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _anims[i],
              builder: (_, _) => Transform.translate(
                offset: Offset(0, _anims[i].value),
                child: Container(
                  width: 7,
                  height: 7,
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  decoration: BoxDecoration(
                    color:
                        (isDark
                                ? AppColors.textSecondaryLight
                                : AppColors.textSecondaryDark)
                            .withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
