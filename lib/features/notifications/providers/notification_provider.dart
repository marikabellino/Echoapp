import 'package:echo/core/services/fcm_service.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/notifications/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsNotifier extends Notifier<List<AppNotification>> {
  late final NotificationService _service;

  @override
  List<AppNotification> build() {
    _service = NotificationService(Supabase.instance.client);
    ref.onDispose(_service.dispose);

    Future.microtask(() async {
      // Realtime (in-app)
      await _service.initialize(onNotification: add);
      // FCM (foreground intercept — background/killed gestito dall'OS)
      await FcmService.initialize(onNotification: add);
    });

    return [];
  }

  void add(AppNotification notification) {
    if (state.any((n) => n.id == notification.id)) return;
    state = [notification, ...state];
  }

  void markAllRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  void markRead(String id) {
    state = [
      for (final n in state) n.id == id ? n.copyWith(isRead: true) : n,
    ];
  }

  void clear() => state = [];
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, List<AppNotification>>(
  NotificationsNotifier.new,
);

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((n) => !n.isRead).length;
});
