import 'dart:async';

import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/messaging/data/gif_search_service.dart';
import 'package:echo/features/messaging/data/messaging_repository.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/domain/models/message_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(ref.watch(supabaseClientProvider)),
);

final gifSearchServiceProvider = Provider<GifSearchService>(
  (ref) => GifSearchService(),
);

// ─── Conversations list ───────────────────────────────────────────────────────

class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  RealtimeChannel? _channel;

  @override
  Future<List<ConversationModel>> build() async {
    final repo = ref.watch(messagingRepositoryProvider);

    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOffline = prev?.asData?.value == false;
      final isNowOnline = next.asData?.value == true;
      if (wasOffline && isNowOnline) ref.invalidateSelf();
    });

    _channel = repo.subscribeToAllMessages(() => ref.invalidateSelf());

    ref.onDispose(() {
      if (_channel != null) repo.removeChannel(_channel!);
    });

    return repo.getConversations();
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationModel>>(
      ConversationsNotifier.new,
    );

/// Totale messaggi non letti (per badge nella navbar).
final totalUnreadCountProvider = Provider<int>((ref) {
  return ref
      .watch(conversationsProvider)
      .maybeWhen(
        data: (convs) => convs.fold(0, (sum, c) => sum + c.unreadCount),
        orElse: () => 0,
      );
});

// ─── Chat state ───────────────────────────────────────────────────────────────

class ChatState {
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final bool isOtherTyping;
  final bool hasMore;
  final bool isLoadingMore;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isSending = false,
    this.isOtherTyping = false,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.error,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    bool? isOtherTyping,
    bool? hasMore,
    bool? isLoadingMore,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      isOtherTyping: isOtherTyping ?? this.isOtherTyping,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
    );
  }
}

// ─── Chat notifier ────────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<ChatState> {
  ChatNotifier(this.conversationId, this.otherUserId);

  static const _pageSize = 50;

  final String conversationId;
  final String otherUserId;
  RealtimeChannel? _channel;
  RealtimeChannel? _typingChannel;
  Timer? _typingResetTimer;

  @override
  ChatState build() {
    _loadMessages();
    _subscribeRealtime();
    _subscribeTyping();

    // Re-check block status every time the chat is opened so the other
    // party's input bar reflects the current state without waiting for
    // the next message.
    ref.invalidate(connectionStatusProvider(otherUserId));

    ref.onDispose(() {
      final repo = ref.read(messagingRepositoryProvider);
      if (_channel != null) repo.removeChannel(_channel!);
      if (_typingChannel != null) repo.removeChannel(_typingChannel!);
      _typingResetTimer?.cancel();
    });

    return const ChatState();
  }

  void _subscribeTyping() {
    final repo = ref.read(messagingRepositoryProvider);
    final currentId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';

    _typingChannel = repo.subscribeToTyping(conversationId, currentId, () {
      state = state.copyWith(isOtherTyping: true);
      _typingResetTimer?.cancel();
      _typingResetTimer = Timer(const Duration(seconds: 3), () {
        state = state.copyWith(isOtherTyping: false);
      });
    });
  }

  Future<void> notifyTyping() async {
    final channel = _typingChannel;
    if (channel == null) return;
    final currentId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    await ref.read(messagingRepositoryProvider).sendTyping(channel, currentId);
  }

  Future<void> _loadMessages() async {
    final repo = ref.read(messagingRepositoryProvider);
    try {
      final msgs = await repo.getMessages(conversationId, limit: _pageSize);
      // DB ritorna DESC (newest first); invertiamo per avere oldest→newest
      state = state.copyWith(
        messages: msgs.reversed.toList(),
        isLoading: false,
        hasMore: msgs.length == _pageSize,
      );
      await repo.markMessagesRead(conversationId);
      ref.invalidate(conversationsProvider);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // Carica la pagina di messaggi precedente quando si risale in cima alla
  // cronologia già scaricata — prima non esisteva alcuna chiamata a questo
  // percorso (già supportato dal repository) e oltre i primi 50 messaggi la
  // cronologia più vecchia restava irraggiungibile scrollando in su.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    final repo = ref.read(messagingRepositoryProvider);
    try {
      final oldest = state.messages.first.createdAt;
      final older = await repo.getMessages(
        conversationId,
        limit: _pageSize,
        before: oldest,
      );
      state = state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMore: older.length == _pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void _subscribeRealtime() {
    final repo = ref.read(messagingRepositoryProvider);
    final currentId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';

    _channel = repo.subscribeToMessages(conversationId, (msg) {
      // Evita duplicati di messaggi già presenti con ID reale
      if (state.messages.any((m) => m.id == msg.id)) return;

      if (msg.senderId == currentId) {
        // Messaggio inviato da noi: sostituisce il placeholder ottimistico (tmp_)
        // invece di aggiungere un secondo messaggio.
        final withoutOptimistic = state.messages
            .where((m) => !m.id.startsWith('tmp_'))
            .toList();
        state = state.copyWith(messages: [...withoutOptimistic, msg]);
      } else {
        // Forza un re-fetch dello stato di blocco: se l'utente è stato bloccato
        // durante la conversazione, la sua UI si aggiornerà al prossimo rebuild.
        ref.invalidate(connectionStatusProvider(otherUserId));
        // Il messaggio viene aggiunto solo se il mittente non è bloccato.
        unawaited(_handleIncomingMessage(msg, repo));
      }
    });
  }

  Future<void> _handleIncomingMessage(
    MessageModel msg,
    MessagingRepository repo,
  ) async {
    try {
      final status = await ref
          .read(connectionRepositoryProvider)
          .getStatus(otherUserId);
      if (status == ConnectionStatus.blocked ||
          status == ConnectionStatus.blockedByThem) {
        return;
      }
      state = state.copyWith(messages: [...state.messages, msg]);
      await repo.markMessagesRead(conversationId);
      ref.invalidate(conversationsProvider);
    } catch (_) {
      // Notifier già disposed o errore di rete: ignora silenziosamente.
    }
  }

  Future<void> sendMessage(String content) => _send(content: content);

  Future<void> sendGif(String gifUrl) => _send(content: '', gifUrl: gifUrl);

  Future<void> _send({required String content, String? gifUrl}) async {
    if (content.trim().isEmpty && gifUrl == null) return;

    final repo = ref.read(messagingRepositoryProvider);
    final currentUserId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';

    final optimistic = MessageModel(
      id: 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: currentUserId,
      content: content.trim(),
      gifUrl: gifUrl,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      isSending: true,
    );

    try {
      final sent = await repo.sendMessage(
        conversationId,
        content,
        gifUrl: gifUrl,
      );
      final withoutOptimistic = state.messages
          .where((m) => m.id != optimistic.id)
          .toList();
      state = state.copyWith(
        messages: [...withoutOptimistic, sent],
        isSending: false,
      );
    } catch (_) {
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != optimistic.id).toList(),
        isSending: false,
        error: 'Errore durante l\'invio',
      );
    }
  }
}

// Riverpod 3: family senza codegen — la chiave è (conversationId, otherUserId)
// autoDispose: senza, il notifier (e la sua subscription realtime che marca i
// messaggi come letti) restava vivo anche dopo aver chiuso la chat, marcando
// come letti messaggi mai visti mentre si era altrove nell'app.
final chatProvider =
    NotifierProvider.autoDispose
        .family<ChatNotifier, ChatState, (String, String)>(
          (args) => ChatNotifier(args.$1, args.$2),
        );
