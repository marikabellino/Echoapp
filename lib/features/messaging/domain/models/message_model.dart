class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? gifUrl;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? replyToId;
  final String? sharedDropId;
  final double? locationLat;
  final double? locationLng;
  final String? locationLabel;
  // Popolato dalla select con embed (cronologia, invio); assente sui payload
  // Realtime "grezzi" (solo colonne), dove va risolto lato client cercando
  // replyToId tra i messaggi già caricati — vedi ChatNotifier._resolveReply.
  final MessageModel? replyTo;

  bool get isRead => readAt != null;
  bool get isGif => gifUrl != null;
  bool get isSharedDrop => sharedDropId != null;
  bool get isLocation => locationLat != null && locationLng != null;
  bool get isAttachment => isSharedDrop || isLocation;

  String get previewText {
    if (isGif) return 'GIF';
    if (isSharedDrop) return 'Drop condiviso';
    if (isLocation) return locationLabel ?? 'Posizione';
    return content;
  }

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
    this.sharedDropId,
    this.locationLat,
    this.locationLng,
    this.locationLabel,
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
      sharedDropId: json['shared_drop_id'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      locationLabel: json['location_label'] as String?,
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
      sharedDropId: sharedDropId,
      locationLat: locationLat,
      locationLng: locationLng,
      locationLabel: locationLabel,
    );
  }
}
