import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/domain/models/message_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingRepository {
  final SupabaseClient _client;

  MessagingRepository(this._client);

  String get _currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw Exception('Non autenticato');
    return id;
  }

  Future<String> getOrCreateConversation(String otherUserId) async {
    final result = await _client.rpc(
      'get_or_create_conversation',
      params: {'other_user_id': otherUserId},
    );
    return result as String;
  }

  Future<List<ConversationModel>> getConversations() async {
    final rows = await _client.rpc('get_conversations');
    return (rows as List<dynamic>)
        .map((r) =>
            ConversationModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<MessageModel>> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final List<dynamic> rows;
    final base = _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    if (before != null) {
      rows = await base
          .lt('created_at', before.toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);
    } else {
      rows = await base
          .order('created_at', ascending: false)
          .limit(limit);
    }
    return rows
        .map((r) => MessageModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> sendMessage(String conversationId, String content) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _currentUserId,
      'content': content.trim(),
    });
  }

  Future<void> markMessagesRead(String conversationId) async {
    await _client.rpc(
      'mark_messages_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  // Sottoscrive ai nuovi messaggi di una conversazione.
  // Ritorna il channel per poterlo chiudere in dispose.
  RealtimeChannel subscribeToMessages(
    String conversationId,
    void Function(MessageModel) onNew,
  ) {
    return _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              final msg = MessageModel.fromJson(
                Map<String, dynamic>.from(payload.newRecord),
              );
              onNew(msg);
            } catch (_) {}
          },
        )
        .subscribe();
  }

  // Sottoscrive a qualsiasi nuovo messaggio dell'utente corrente per
  // aggiornare la lista conversazioni in tempo reale.
  RealtimeChannel subscribeToAllMessages(void Function() onChange) {
    return _client
        .channel('messages:all:$_currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  // ─── Typing broadcast ────────────────────────────────────────────────────────

  RealtimeChannel subscribeToTyping(
    String conversationId,
    String currentUserId,
    void Function() onOtherTyping,
  ) {
    return _client
        .channel('chat_typing:$conversationId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['sender_id'] as String?;
            if (senderId != null && senderId != currentUserId) {
              onOtherTyping();
            }
          },
        )
        .subscribe();
  }

  Future<void> sendTyping(RealtimeChannel channel, String senderId) async {
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'sender_id': senderId},
      );
    } catch (_) {}
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
