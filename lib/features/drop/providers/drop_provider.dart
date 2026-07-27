import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/services/drop_cache_service.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/data/drop_repository.dart';
import 'package:echo/features/drop/domain/models/comment_model.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dropRepositoryProvider = Provider<DropRepository>(
  (ref) => DropRepository(ref.watch(supabaseClientProvider)),
);

// ─── Discover feed ────────────────────────────────────────────────────────────

class DiscoverNotifier extends AsyncNotifier<List<DropModel>> {
  @override
  Future<List<DropModel>> build() =>
      ref.watch(dropRepositoryProvider).getDiscoverDrops();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dropRepositoryProvider).getDiscoverDrops(),
    );
  }

  Future<void> toggleLike(String dropId, {required bool currentlyLiked}) async {
    await ref.read(dropRepositoryProvider).toggleLike(
      dropId,
      isLiked: currentlyLiked,
    );
    ref.invalidate(likersProvider(dropId));
    state = state.whenData(
      (list) => list
          .map(
            (m) => m.id != dropId
                ? m
                : m.copyWith(
                    isLikedByMe: !currentlyLiked,
                    likesCount: currentlyLiked
                        ? (m.likesCount - 1).clamp(0, 9999)
                        : m.likesCount + 1,
                  ),
          )
          .toList(),
    );
  }

  void updateCommentCount(String dropId, int delta) {
    state = state.whenData(
      (list) => list
          .map(
            (m) => m.id != dropId
                ? m
                : m.copyWith(
                    commentsCount: (m.commentsCount + delta).clamp(0, 9999),
                  ),
          )
          .toList(),
    );
  }
}

final discoverProvider =
    AsyncNotifierProvider<DiscoverNotifier, List<DropModel>>(
      DiscoverNotifier.new,
    );

// ─── Nearby drops for map ─────────────────────────────────────────────────────

final nearbyDropsProvider =
    FutureProvider.family<List<DropModel>, ({double lat, double lng})>(
      (ref, coords) => ref
          .watch(dropRepositoryProvider)
          .getNearbyDrops(lat: coords.lat, lng: coords.lng),
    );

// ─── User drops for profile (offline-aware) ──────────────────────────────────

final userDropsProvider = FutureProvider.family<List<DropModel>, String>(
  (ref, userId) async {
    final isOnline = ref.watch(isOnlineProvider);
    if (!isOnline) {
      return ref.read(dropCacheServiceProvider).loadUserDrops(userId);
    }
    final drops =
        await ref.read(dropRepositoryProvider).getUserDrops(userId);
    ref.read(dropCacheServiceProvider).saveUserDrops(userId, drops);
    return drops;
  },
);

// ─── Single drop by id ────────────────────────────────────────────────────────

final dropByIdProvider = FutureProvider.family<DropModel?, String>(
  (ref, dropId) => ref.read(dropRepositoryProvider).getDropById(dropId),
);

// ─── Tag persone ──────────────────────────────────────────────────────────────

// Drop in cui l'utente è taggato (esclusi quelli nascosti dal suo profilo).
final taggedDropsProvider = FutureProvider.family<List<DropModel>, String>(
  (ref, userId) =>
      ref.read(dropRepositoryProvider).getTaggedDrops(userId),
);

// Persone taggate in un drop specifico (mostrate nella detail sheet).
final dropTagsProvider = FutureProvider.family<List<ProfileModel>, String>(
  (ref, dropId) => ref.read(dropRepositoryProvider).getDropTags(dropId),
);

// ─── Likes ────────────────────────────────────────────────────────────────────

// Persone che hanno messo like a un drop specifico (per "Piace a @..." + sheet).
final likersProvider = FutureProvider.family<List<ProfileModel>, String>(
  (ref, dropId) => ref.read(dropRepositoryProvider).getLikers(dropId),
);

// ─── Comments per drop ────────────────────────────────────────────────────────

class CommentsNotifier extends AsyncNotifier<List<CommentModel>> {
  CommentsNotifier(this.dropId);
  final String dropId;

  @override
  Future<List<CommentModel>> build() =>
      ref.read(dropRepositoryProvider).getComments(dropId);

  Future<void> addComment(
    String content, {
    List<String> taggedUserIds = const [],
  }) async {
    final repo = ref.read(dropRepositoryProvider);
    final commentId = await repo.addComment(dropId, content);
    if (taggedUserIds.isNotEmpty) {
      // Il commento è già stato pubblicato: un errore nel tag non deve
      // impedire il reset del composer, stesso principio di create_page.dart.
      try {
        await repo.tagUsersOnComment(commentId, taggedUserIds);
      } catch (_) {}
    }
    ref.invalidateSelf();
  }

  Future<void> deleteComment(String commentId) async {
    await ref.read(dropRepositoryProvider).deleteComment(commentId);
    state = state.whenData(
      (list) => list.where((c) => c.id != commentId).toList(),
    );
  }
}

final commentsProvider =
    AsyncNotifierProvider.family<CommentsNotifier, List<CommentModel>, String>(
  (id) => CommentsNotifier(id),
);
