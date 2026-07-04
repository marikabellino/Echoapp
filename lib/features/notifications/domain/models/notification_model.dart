enum NotificationType { like, connectionRequest, proximity, message }

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? dropId;
  final String? fromUserId;
  final String? fromUsername;
  final String? conversationId;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.dropId,
    this.fromUserId,
    this.fromUsername,
    this.conversationId,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    dropId: dropId,
    fromUserId: fromUserId,
    fromUsername: fromUsername,
    conversationId: conversationId,
  );
}
