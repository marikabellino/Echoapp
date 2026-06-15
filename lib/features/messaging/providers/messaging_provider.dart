import 'package:apptest/features/auth/providers/auth_provider.dart';
import 'package:apptest/features/messaging/data/messaging_repository.dart';
import 'package:apptest/features/messaging/domain/models/conversation_model.dart';
import 'package:apptest/features/messaging/domain/models/message_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(ref.watch(supabaseClientProvider)),
);

// ─── Conversations list ───────────────────────────────────────────────────────

class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  RealtimeChannel? _channel;

  @override
  Future<List<ConversationModel>> build() async {
    final repo = ref.watch(messagingRepositoryProvider);

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
  return ref.watch(conversationsProvider).maybeWhen(
        data: (convs) => convs.fold(0, (sum, c) => sum + c.unreadCount),
        orElse: () => 0,
      );
});

// ─── Chat state ───────────────────────────────────────────────────────────────

class ChatState {
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isSending = false,
    this.error,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

// ─── Chat notifier ────────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<ChatState> {
  ChatNotifier(this.conversationId);

  final String conversationId;
  RealtimeChannel? _channel;

  @override
  ChatState build() {
    _loadMessages();
    _subscribeRealtime();

    ref.onDispose(() {
      if (_channel != null) {
        ref.read(messagingRepositoryProvider).removeChannel(_channel!);
      }
    });

    return const ChatState();
  }

  Future<void> _loadMessages() async {
    final repo = ref.read(messagingRepositoryProvider);
    try {
      final msgs = await repo.getMessages(conversationId);
      // DB ritorna DESC (newest first); invertiamo per avere oldest→newest
      state = state.copyWith(
        messages: msgs.reversed.toList(),
        isLoading: false,
      );
      await repo.markMessagesRead(conversationId);
      ref.invalidate(conversationsProvider);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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
        final withoutOptimistic =
            state.messages.where((m) => !m.id.startsWith('tmp_')).toList();
        state = state.copyWith(messages: [...withoutOptimistic, msg]);
      } else {
        // Messaggio ricevuto: aggiunge normalmente e lo marca come letto
        state = state.copyWith(messages: [...state.messages, msg]);
        repo.markMessagesRead(conversationId);
        ref.invalidate(conversationsProvider);
      }
    });
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final repo = ref.read(messagingRepositoryProvider);
    final currentUserId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';

    final optimistic = MessageModel(
      id: 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: currentUserId,
      content: content.trim(),
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      isSending: true,
    );

    try {
      await repo.sendMessage(conversationId, content);
      state = state.copyWith(isSending: false);
    } catch (_) {
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != optimistic.id).toList(),
        isSending: false,
        error: 'Errore durante l\'invio',
      );
    }
  }
}

// Riverpod 3: family senza codegen — il factory riceve l'arg e crea il notifier
final chatProvider =
    NotifierProvider.family<ChatNotifier, ChatState, String>(
  (id) => ChatNotifier(id),
);
