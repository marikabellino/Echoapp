class ConversationModel {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final String? lastMessageGifUrl;
  final DateTime? lastMessageAt;
  final int unreadCount;

  String get otherName =>
      otherDisplayName.isNotEmpty ? otherDisplayName : otherUsername;

  // Un messaggio-GIF ha content vuoto (vedi sendGif in messaging_provider),
  // quindi lastMessage da solo non basta a distinguerlo da "nessun testo".
  bool get lastMessageIsGif => lastMessageGifUrl != null;

  const ConversationModel({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageGifUrl,
    this.lastMessageAt,
    this.unreadCount = 0,
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
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
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
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
