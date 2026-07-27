import 'package:echo/core/router/app_router.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/messaging/domain/models/conversation_model.dart';
import 'package:echo/features/messaging/presentation/pages/chat_page.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Naviga al contenuto puntato da una notifica (usata per il tap su una push
// FCM ricevuta in background/killed, dove non esiste un BuildContext locale a
// cui agganciarsi — si usa il Navigator radice). Rispecchia la logica di tap
// già presente in notifications_page.dart.
Future<void> navigateForNotification(
  Ref ref,
  AppNotification notification,
) async {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;

  switch (notification.type) {
    case NotificationType.message:
      final fromId = notification.fromUserId;
      final convId = notification.conversationId;
      if (fromId == null || convId == null) return;
      final fromName = notification.fromUsername ?? '';
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversation: ConversationModel(
              id: convId,
              otherUserId: fromId,
              otherUsername: fromName,
              otherDisplayName: fromName,
            ),
          ),
        ),
      );
    case NotificationType.connectionRequest:
    case NotificationType.like:
      final fromId = notification.fromUserId;
      if (fromId == null) return;
      final profile = await ref.read(profileByIdProvider(fromId).future);
      if (profile == null) return;
      navigator.push(
        MaterialPageRoute(builder: (_) => UserProfilePage(user: profile)),
      );
    case NotificationType.proximity:
    case NotificationType.tagged:
    case NotificationType.circleDrop:
    case NotificationType.commentTagged:
      final dropId = notification.dropId;
      if (dropId == null) return;
      final drop = await ref.read(dropByIdProvider(dropId).future);
      if (drop == null) return;
      ref.read(mapFlyTargetProvider.notifier).set(drop);
      ref.read(shellIndexProvider.notifier).setIndex(1);
  }
}
