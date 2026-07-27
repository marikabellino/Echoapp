import 'package:echo/core/services/notification_navigation.dart';
import 'package:echo/core/services/permission_gate.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level: chiamato in isolato separato quando l'app è killata/in background.
// Firebase mostra automaticamente la notification del payload — nessuna azione aggiuntiva.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage _) async {}

class FcmService {
  // initialize() viene richiamato a ogni login/logout (notificationsProvider
  // viene invalidato per riassociare il token al nuovo utente). I listener
  // di FirebaseMessaging.instance sono però stream GLOBALI dell'SDK, non
  // legati a questa istanza: se li riattaccassimo a ogni chiamata si
  // accumulerebbero, e una singola push finirebbe per generare un toast per
  // ogni ciclo di login/logout fatto nella sessione. Li registriamo quindi
  // una sola volta per processo, ma li facciamo puntare sempre all'ultimo
  // ref/callback ricevuto così restano coerenti con l'utente corrente.
  static bool _listenersRegistered = false;
  static Ref? _ref;
  static void Function(AppNotification)? _onNotification;

  static Future<void> initialize({
    required Ref ref,
    required void Function(AppNotification) onNotification,
  }) async {
    _ref = ref;
    _onNotification = onNotification;

    // Permessi (necessari su iOS e Android 13+)
    await PermissionGate.run(() => FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ));

    // iOS: non mostrare la notifica di sistema quando l'app è in foreground —
    // la gestiamo noi con EchoToast.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // Salva il token FCM nel profilo Supabase (va rifatto a ogni chiamata:
    // è così che il device si riassocia al nuovo utente dopo un login).
    await _saveToken();

    if (_listenersRegistered) return;
    _listenersRegistered = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _saveToken());

    // Messaggi in foreground → EchoToast via callback
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _onNotification?.call(_notificationFromMessage(message));
    });

    // Tap sulla push mentre l'app è in background (non killata).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final currentRef = _ref;
      if (currentRef != null) {
        navigateForNotification(currentRef, _notificationFromMessage(message));
      }
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
      title: n?.title ?? 'Mingle',
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
      'circle_drop' => NotificationType.circleDrop,
      'comment_tagged' => NotificationType.commentTagged,
      _ => NotificationType.like,
    };
  }

  static Future<void> _saveToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('FcmService: getToken() ha restituito null');
        return;
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('FcmService: nessun utente loggato, salvataggio saltato');
        return;
      }
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      debugPrint('FcmService: fcm_token salvato per $userId (${token.substring(0, 12)}...)');
    } catch (e) {
      debugPrint('FcmService: impossibile salvare fcm_token — $e');
    }
  }
}
