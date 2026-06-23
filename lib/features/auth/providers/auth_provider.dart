import 'package:echo/features/auth/data/auth_repository.dart';
import 'package:echo/core/services/ai_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => AiService(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

final currentUserProvider = Provider<User?>(
  (ref) {
    // Re-read when auth state changes
    ref.watch(authStateProvider);
    return Supabase.instance.client.auth.currentUser;
  },
);
