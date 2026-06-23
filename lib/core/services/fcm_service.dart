import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level: chiamato in isolato separato quando l'app è killata/in background.
// Firebase mostra automaticamente la notification del payload — nessuna azione aggiuntiva.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage _) async {}

class FcmService {
  static Future<void> initialize({
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
      onNotification(AppNotification(
        id: 'fcm_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}',
        type: _typeFromData(message.data),
        title: n.title ?? 'Echo',
        body: n.body ?? '',
        createdAt: DateTime.now(),
        fromUserId: message.data['fromUserId'] as String?,
        fromUsername: message.data['fromUsername'] as String?,
        memoryId: message.data['memoryId'] as String?,
      ));
    });
  }

  static NotificationType _typeFromData(Map<String, dynamic> data) {
    return switch (data['type'] as String?) {
      'like' => NotificationType.like,
      'connection_request' => NotificationType.connectionRequest,
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
