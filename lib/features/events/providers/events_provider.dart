import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/events/data/events_repository.dart';
import 'package:echo/features/events/domain/models/event_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) => EventsRepository(ref.watch(supabaseClientProvider)),
);

final nearbyActiveEventsProvider =
    FutureProvider.family<List<EventModel>, ({double lat, double lng})>(
      (ref, coords) => ref
          .watch(eventsRepositoryProvider)
          .getNearbyActiveEvents(lat: coords.lat, lng: coords.lng),
    );

final eventDropsProvider = FutureProvider.family<List<DropModel>, String>(
  (ref, eventId) => ref.watch(eventsRepositoryProvider).getEventDrops(eventId),
);
