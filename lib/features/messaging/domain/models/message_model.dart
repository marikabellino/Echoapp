class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? gifUrl;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? replyToId;
  // Popolato dalla select con embed (cronologia, invio); assente sui payload
  // Realtime "grezzi" (solo colonne), dove va risolto lato client cercando
  // replyToId tra i messaggi già caricati — vedi ChatNotifier._resolveReply.
  final MessageModel? replyTo;

  bool get isRead => readAt != null;
  bool get isGif => gifUrl != null;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.gifUrl,
    required this.createdAt,
    this.readAt,
    this.replyToId,
    this.replyTo,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      gifUrl: json['gif_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      replyToId: json['reply_to_id'] as String?,
      replyTo: json['reply_to'] != null
          ? MessageModel.fromJson(
              Map<String, dynamic>.from(json['reply_to'] as Map),
            )
          : null,
    );
  }

  MessageModel copyWith({MessageModel? replyTo}) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      gifUrl: gifUrl,
      createdAt: createdAt,
      readAt: readAt,
      replyToId: replyToId,
      replyTo: replyTo ?? this.replyTo,
    );
  }
}
