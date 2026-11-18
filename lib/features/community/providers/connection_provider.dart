import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/data/connection_repository.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:echo/features/community/data/connection_repository.dart'
    show ConnectionStatus;

final connectionRepositoryProvider = Provider<ConnectionRepository>(
  (ref) => ConnectionRepository(ref.watch(supabaseClientProvider)),
);

final connectionStatusProvider = FutureProvider.autoDispose
    .family<ConnectionStatus, String>(
      (ref, userId) => ref.read(connectionRepositoryProvider).getStatus(userId),
    );

final myConnectionsProvider = FutureProvider.autoDispose<List<ProfileModel>>(
  (ref) => ref.read(connectionRepositoryProvider).getMyConnections(),
);

final pendingRequestsProvider = FutureProvider.autoDispose<List<ProfileModel>>((
  ref,
) {
  // Le richieste arrivate mentre l'app era in background (push gestita dal
  // sistema, nessun evento in-app) vanno ricaricate al rientro nell'app.
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.read(connectionRepositoryProvider).getPendingRequests();
});

final blockedUsersProvider = FutureProvider.autoDispose<List<ProfileModel>>(
  (ref) => ref.read(connectionRepositoryProvider).getBlockedUsers(),
);
