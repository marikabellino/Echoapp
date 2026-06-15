import 'package:apptest/features/profile/domain/models/profile_model.dart';
import 'package:apptest/features/profile/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;

// ─── Search history ───────────────────────────────────────────────────────────

class SearchHistoryNotifier extends Notifier<List<ProfileModel>> {
  static const int _max = 8;

  @override
  List<ProfileModel> build() => [];

  void add(ProfileModel user) {
    final updated = [user, ...state.where((u) => u.id != user.id)];
    state = updated.take(_max).toList();
  }

  void clear() => state = [];
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<ProfileModel>>(
  SearchHistoryNotifier.new,
);

const _kPageSize = 20;

// ─── State ────────────────────────────────────────────────────────────────────

class UserSearchState {
  final List<ProfileModel> users;
  final bool hasMore;
  final bool isLoadingMore;
  final String query;

  const UserSearchState({
    this.users = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.query = '',
  });

  UserSearchState copyWith({
    List<ProfileModel>? users,
    bool? hasMore,
    bool? isLoadingMore,
    String? query,
  }) =>
      UserSearchState(
        users: users ?? this.users,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        query: query ?? this.query,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class UserSearchNotifier extends AsyncNotifier<UserSearchState> {
  double? _lat;
  double? _lng;
  int _offset = 0;

  @override
  Future<UserSearchState> build() async {
    await _initLocation();
    return const UserSearchState();
  }

  Future<void> _initLocation() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm != geo.LocationPermission.always &&
          perm != geo.LocationPermission.whileInUse) {
        return;
      }
      final last = await geo.Geolocator.getLastKnownPosition();
      if (last != null) {
        _lat = last.latitude;
        _lng = last.longitude;
        _syncLocationSilently();
        return;
      }
      final pos = await geo.Geolocator.getCurrentPosition();
      _lat = pos.latitude;
      _lng = pos.longitude;
      _syncLocationSilently();
    } catch (_) {}
  }

  void _syncLocationSilently() {
    if (_lat == null || _lng == null) return;
    ref
        .read(profileRepositoryProvider)
        .updateLocation(_lat!, _lng!)
        .ignore();
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  Future<void> search(String query) async {
    _offset = 0;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final users = await _fetchPage(query, 0);
      _offset = users.length;
      return UserSearchState(
        users: users,
        hasMore: users.length == _kPageSize,
        query: query,
      );
    });
  }

  Future<void> loadMore() async {
    final current = switch (state) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final more = await _fetchPage(current.query, _offset);
      _offset += more.length;
      state = AsyncData(current.copyWith(
        users: [...current.users, ...more],
        hasMore: more.length == _kPageSize,
        isLoadingMore: false,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  void reset() {
    _offset = 0;
    state = const AsyncData(UserSearchState());
  }

  Future<List<ProfileModel>> _fetchPage(String query, int offset) =>
      ref.read(profileRepositoryProvider).searchUsersNearby(
            query: query,
            lat: _lat,
            lng: _lng,
            pageSize: _kPageSize,
            offset: offset,
          );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final userSearchProvider =
    AsyncNotifierProvider.autoDispose<UserSearchNotifier, UserSearchState>(
  UserSearchNotifier.new,
);
