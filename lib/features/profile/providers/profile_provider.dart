import 'dart:typed_data';

import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/profile/data/profile_repository.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

// ─── Current user profile ─────────────────────────────────────────────────────

class CurrentProfileNotifier extends AsyncNotifier<ProfileModel?> {
  @override
  Future<ProfileModel?> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;
    return ref.watch(profileRepositoryProvider).getProfile(user.id);
  }

  Future<void> saveProfile({
    required String displayName,
    required String bio,
    String? avatarUrl,
  }) async {
    final updated = await ref.read(profileRepositoryProvider).updateProfile(
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl,
    );
    state = AsyncData(updated);
  }

  Future<String> uploadAvatar(List<int> bytes) async {
    return ref
        .read(profileRepositoryProvider)
        .uploadAvatar(Uint8List.fromList(bytes));
  }
}

final currentProfileProvider =
    AsyncNotifierProvider<CurrentProfileNotifier, ProfileModel?>(
      CurrentProfileNotifier.new,
    );

// ─── Any user profile (for viewing others) ───────────────────────────────────

final profileByIdProvider = FutureProvider.family<ProfileModel?, String>(
  (ref, userId) => ref.watch(profileRepositoryProvider).getProfile(userId),
);
