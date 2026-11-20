class ConversationModel {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final String? lastMessageGifUrl;
  final String? lastMessageKind;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// 'accepted' = chat normale; 'pending' = richiesta di messaggio da chi non
  /// è nella cerchia, in attesa che l'altra persona la accetti.
  final String status;
  final String? requestedBy;

  bool get isPending => status == 'pending';

  /// Richiesta ricevuta da [myId] e non ancora accettata.
  bool isIncomingRequest(String myId) =>
      isPending && requestedBy != null && requestedBy != myId;

  String get otherName =>
      otherDisplayName.isNotEmpty ? otherDisplayName : otherUsername;

  // Un messaggio-GIF ha content vuoto (vedi sendGif in messaging_provider),
  // quindi lastMessage da solo non basta a distinguerlo da "nessun testo".
  bool get lastMessageIsGif => lastMessageGifUrl != null;
  bool get lastMessageIsDrop => lastMessageKind == 'drop';
  bool get lastMessageIsLocation => lastMessageKind == 'location';

  const ConversationModel({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageGifUrl,
    this.lastMessageKind,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.status = 'accepted',
    this.requestedBy,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['conversation_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherUsername: json['other_username'] as String? ?? '',
      otherDisplayName: json['other_display_name'] as String? ?? '',
      otherAvatarUrl: json['other_avatar_url'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageGifUrl: json['last_message_gif_url'] as String?,
      lastMessageKind: json['last_message_kind'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'accepted',
      requestedBy: json['requested_by'] as String?,
    );
  }

  ConversationModel copyWith({
    String? lastMessage,
    String? lastMessageGifUrl,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return ConversationModel(
      id: id,
      otherUserId: otherUserId,
      otherUsername: otherUsername,
      otherDisplayName: otherDisplayName,
      otherAvatarUrl: otherAvatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageGifUrl: lastMessageGifUrl ?? this.lastMessageGifUrl,
      lastMessageKind: lastMessageKind,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      status: status,
      requestedBy: requestedBy,
    );
  }
}

/// Cosa può fare l'utente in una conversazione: è una chat normale, una
/// richiesta di messaggio, e può scrivere adesso?
class ConversationGate {
  final String status;
  final String? requestedBy;
  final bool canSend;

  const ConversationGate({
    required this.status,
    required this.requestedBy,
    required this.canSend,
  });

  bool isIncomingRequest(String myId) =>
      status == 'pending' &&
      requestedBy != null &&
      requestedBy != myId &&
      !canSend;

  bool isOutgoingRequest(String myId) =>
      status == 'pending' && requestedBy == myId;
}

/// Errore con un messaggio già pronto da mostrare all'utente.
class MessagingException implements Exception {
  const MessagingException(this.message);
  final String message;

  @override
  String toString() => message;
}
