import 'dart:async';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/domain/models/message_model.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_controller.text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 300), () {
      ref
          .read(chatProvider((widget.conversation.id, widget.conversation.otherUserId)).notifier)
          .notifyTyping();
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        pos,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(pos);
    }
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
        .read(chatProvider((widget.conversation.id, widget.conversation.otherUserId)).notifier)
        .sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = ref.watch(chatProvider((widget.conversation.id, widget.conversation.otherUserId)));
    final currentUserId =
        ref.watch(currentUserProvider)?.id ?? '';

    // Scrolla in fondo quando arrivano nuovi messaggi
    ref.listen(chatProvider((widget.conversation.id, widget.conversation.otherUserId)), (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(),
        );
      }
    });

    final conv = widget.conversation;
    final blockStatus = ref
        .watch(connectionStatusProvider(conv.otherUserId))
        .asData
        ?.value;
    final isBlocked = blockStatus == ConnectionStatus.blocked ||
        blockStatus == ConnectionStatus.blockedByThem;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AnimatedGradientBackground(
        child: Column(
          children: [
            _ChatAppBar(conversation: conv, isDark: isDark),
            Expanded(
              child: chatState.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 2,
                      ),
                    )
                  : chatState.messages.isEmpty
                      ? Center(
                          child: Text(
                            'Nessun messaggio.\nDi\' ciao!',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySecondary(context),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: chatState.messages.length +
                              (chatState.isOtherTyping ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (chatState.isOtherTyping &&
                                i == chatState.messages.length) {
                              return const _TypingIndicator();
                            }
                            final msg = chatState.messages[i];
                            final isMine = msg.senderId == currentUserId;
                            final isOptimistic =
                                msg.id.startsWith('tmp_');
                            final showTime = i == 0 ||
                                msg.createdAt
                                        .difference(
                                          chatState.messages[i - 1].createdAt,
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
              ),
          ],
        ),
      ),
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({required this.conversation, required this.isDark});

  final ConversationModel conversation;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.55)
                  : AppColors.lightSurface.withValues(alpha: 0.85),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Theme.of(context).dividerColor
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage: conversation.otherAvatarUrl != null
                      ? CachedNetworkImageProvider(
                          conversation.otherAvatarUrl!,
                        )
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
                    style: AppTextStyles.body(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
              style: AppTextStyles.bodySecondary(context).copyWith(
                fontSize: 11,
              ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.accent
                    : (isDark
                        ? AppColors.darkSurfaceLight
                        : AppColors.lightSurface),
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
                            : (isDark
                                ? AppColors.textLight
                                : AppColors.textDark),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Opacity(
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isSending;
  final VoidCallback onSend;

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
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Theme.of(context).dividerColor
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceLight.withValues(alpha: 0.7)
                          : AppColors.lightSurface,
                      borderRadius:
                          BorderRadius.circular(AppRadius.xl),
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
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Theme.of(context).dividerColor
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
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
          (c) => Tween<double>(begin: 0, end: -6).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) { _dots[i].repeat(reverse: true); }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _dots) { c.dispose(); }
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
                    color: (isDark
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
