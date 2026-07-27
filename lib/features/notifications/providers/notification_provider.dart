import 'package:echo/core/services/fcm_service.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/notifications/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsNotifier extends Notifier<List<AppNotification>> {
  NotificationService? _service;

  @override
  List<AppNotification> build() {
    // Il provider viene invalidato (e quindi ricostruito) sia al login che
    // al logout per staccare/riattaccare le subscription al giusto utente —
    // niente "late final": build() su questa stessa istanza può girare più
    // di una volta nello stesso processo, e serve chiudere il vecchio
    // service prima di sostituirlo per non perdere i channel realtime aperti.
    _service?.dispose();
    final service = NotificationService(Supabase.instance.client);
    _service = service;
    ref.onDispose(service.dispose);

    Future.microtask(() async {
      // Realtime (in-app)
      await service.initialize(onNotification: _handleIncoming);
      // FCM (foreground intercept — background/killed gestito dall'OS)
      await FcmService.initialize(ref: ref, onNotification: _handleIncoming);
    });

    return [];
  }

  // I messaggi hanno già una loro sezione dedicata (tab Messaggi, con badge
  // non-letti proprio) — mostriamo comunque il toast ma non li duplichiamo
  // nel centro notifiche.
  void _handleIncoming(AppNotification notification) {
    ref.read(notificationToastProvider.notifier).show(notification);

    // ProfilePage resta "viva" per tutta la sessione (i tab del MainShell
    // sono keep-alive), quindi taggedDropsProvider è cache-ata dalla prima
    // apertura e non si aggiornerebbe mai da sola quando arriva un nuovo tag.
    if (notification.type == NotificationType.tagged) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) ref.invalidate(taggedDropsProvider(userId));
    }

    if (notification.type == NotificationType.message) return;
    add(notification);
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

// Veicola l'ultima notifica in arrivo per il toast, senza passare dalla lista
// persistita del centro notifiche (che esclude i messaggi).
class ToastNotifier extends Notifier<AppNotification?> {
  @override
  AppNotification? build() => null;

  void show(AppNotification notification) => state = notification;
}

final notificationToastProvider =
    NotifierProvider<ToastNotifier, AppNotification?>(ToastNotifier.new);
