import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/memory/data/memory_repository.dart';
import 'package:echo/features/memory/domain/models/comment_model.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>(
  (ref) => MemoryRepository(ref.watch(supabaseClientProvider)),
);

// ─── Discover feed ────────────────────────────────────────────────────────────

class DiscoverNotifier extends AsyncNotifier<List<MemoryModel>> {
  @override
  Future<List<MemoryModel>> build() =>
      ref.watch(memoryRepositoryProvider).getDiscoverMemories();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(memoryRepositoryProvider).getDiscoverMemories(),
    );
  }

  Future<void> toggleLike(String memoryId, {required bool currentlyLiked}) async {
    await ref.read(memoryRepositoryProvider).toggleLike(
      memoryId,
      isLiked: currentlyLiked,
    );
    state = state.whenData(
      (list) => list
          .map(
            (m) => m.id != memoryId
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

  void updateCommentCount(String memoryId, int delta) {
    state = state.whenData(
      (list) => list
          .map(
            (m) => m.id != memoryId
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
    AsyncNotifierProvider<DiscoverNotifier, List<MemoryModel>>(
      DiscoverNotifier.new,
    );

// ─── Nearby memories for map ─────────────────────────────────────────────────

final nearbyMemoriesProvider =
    FutureProvider.family<List<MemoryModel>, ({double lat, double lng})>(
      (ref, coords) => ref
          .watch(memoryRepositoryProvider)
          .getNearbyMemories(lat: coords.lat, lng: coords.lng),
    );

// ─── User memories for profile ───────────────────────────────────────────────

final userMemoriesProvider = FutureProvider.family<List<MemoryModel>, String>(
  (ref, userId) =>
      ref.watch(memoryRepositoryProvider).getUserMemories(userId),
);

// ─── Comments per memory ─────────────────────────────────────────────────────

class CommentsNotifier extends AsyncNotifier<List<CommentModel>> {
  CommentsNotifier(this.memoryId);
  final String memoryId;

  @override
  Future<List<CommentModel>> build() =>
      ref.read(memoryRepositoryProvider).getComments(memoryId);

  Future<void> addComment(String content) async {
    await ref.read(memoryRepositoryProvider).addComment(memoryId, content);
    ref.invalidateSelf();
  }

  Future<void> deleteComment(String commentId) async {
    await ref.read(memoryRepositoryProvider).deleteComment(commentId);
    state = state.whenData(
      (list) => list.where((c) => c.id != commentId).toList(),
    );
  }
}

final commentsProvider =
    AsyncNotifierProvider.family<CommentsNotifier, List<CommentModel>, String>(
  (id) => CommentsNotifier(id),
);
