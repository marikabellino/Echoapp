class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? gifUrl;
  final DateTime createdAt;
  final DateTime? readAt;

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
    );
  }
}
