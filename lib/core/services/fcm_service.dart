import 'package:echo/core/services/notification_navigation.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level: chiamato in isolato separato quando l'app è killata/in background.
// Firebase mostra automaticamente la notification del payload — nessuna azione aggiuntiva.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage _) async {}

class FcmService {
  static Future<void> initialize({
    required Ref ref,
    required void Function(AppNotification) onNotification,
  }) async {
    // Permessi (necessari su iOS e Android 13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOS: non mostrare la notifica di sistema quando l'app è in foreground —
    // la gestiamo noi con EchoToast.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // Salva il token FCM nel profilo Supabase
    await _saveToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _saveToken());

    // Messaggi in foreground → EchoToast via callback
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      onNotification(_notificationFromMessage(message));
    });

    // Tap sulla push mentre l'app è in background (non killata).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      navigateForNotification(ref, _notificationFromMessage(message));
    });

    // App aperta tappando la push da stato killed (cold start).
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      navigateForNotification(
        ref,
        _notificationFromMessage(initialMessage),
      );
    }
  }

  static AppNotification _notificationFromMessage(RemoteMessage message) {
    final n = message.notification;
    final data = message.data;
    return AppNotification(
      id: 'fcm_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}',
      type: _typeFromData(data),
      title: n?.title ?? 'Echo',
      body: n?.body ?? '',
      createdAt: DateTime.now(),
      fromUserId: data['fromUserId'] as String?,
      fromUsername: data['fromUsername'] as String?,
      dropId: data['memoryId'] as String?,
      conversationId: data['conversationId'] as String?,
    );
  }

  static NotificationType _typeFromData(Map<String, dynamic> data) {
    return switch (data['type'] as String?) {
      'like' => NotificationType.like,
      'connection_request' => NotificationType.connectionRequest,
      'message' => NotificationType.message,
      'proximity' => NotificationType.proximity,
      'tagged' => NotificationType.tagged,
      _ => NotificationType.like,
    };
  }

  static Future<void> _saveToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
  }
}
