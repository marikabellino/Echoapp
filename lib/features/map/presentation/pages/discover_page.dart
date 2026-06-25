import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';

import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/community/providers/user_search_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:echo/features/memory/presentation/widgets/comments_sheet.dart';
import 'package:echo/features/memory/providers/memory_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;
  bool _searchActive = false;
  String _searchQuery = '';
  int _tabIndex = 0; // 0 = Cerchia, 1 = Pubblici

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_searchActive) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 250) {
      ref.read(userSearchProvider.notifier).loadMore();
    }
  }

  void _activateSearch() {
    if (_searchActive) return;
    setState(() => _searchActive = true);
  }

  void _onSearchChanged(String val) {
    final trimmed = val.trim();
    setState(() => _searchQuery = trimmed);
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      ref.read(userSearchProvider.notifier).reset();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(userSearchProvider.notifier).search(trimmed);
    });
  }

  void _closeSearch() {
    _focusNode.unfocus();
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
    ref.read(userSearchProvider.notifier).reset();
  }

  void _onUserTap(ProfileModel user, BuildContext context) {
    ref.read(searchHistoryProvider.notifier).add(user);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(user: user)),
    );
  }

  void _onMemoryTap(MemoryModel memory) {
    ref.read(mapFlyTargetProvider.notifier).set(memory);
    ref.read(shellIndexProvider.notifier).setIndex(1);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final memoriesAsync = ref.watch(discoverProvider);
    final searchAsync = ref.watch(userSearchProvider);
    final history = ref.watch(searchHistoryProvider);

    if (!isOnline) {
      return Scaffold(
        body: Stack(
          children: [
            _Background(isDark: isDark),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scopri', style: AppTextStyles.displayLarge(context)),
                    const SizedBox(height: 6),
                    Text(
                      'Ricordi lasciati nel mondo',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ],
                ),
              ),
            ),
            const OfflinePlaceholder(
              message: 'Cerca persone e ricordi non è disponibile offline.',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Scopri',
                            style: AppTextStyles.displayLarge(context),
                          ),
                          const Spacer(),
                          if (_searchActive)
                            GestureDetector(
                              onTap: _closeSearch,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  'Annulla',
                                  style: AppTextStyles.bodySecondary(context)
                                      .copyWith(fontSize: 13),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Align(
                          key: ValueKey(_searchActive),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _searchActive
                                ? 'Trova persone nella community'
                                : 'Ricordi lasciati nel mondo',
                            style: AppTextStyles.bodySecondary(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Search bar ──────────────────────────────────────
                      _SearchBar(
                        controller: _searchController,
                        focusNode: _focusNode,
                        onTap: _activateSearch,
                        onChanged: _onSearchChanged,
                        onClear: _searchActive
                            ? () {
                                _searchController.clear();
                                ref
                                    .read(userSearchProvider.notifier)
                                    .search('');
                              }
                            : null,
                        searchActive: _searchActive,
                      ),
                      SizedBox(height: _searchActive ? 20 : 12),
                      if (!_searchActive) ...[
                        _DiscoverTabRow(
                          tabIndex: _tabIndex,
                          onChanged: (i) => setState(() => _tabIndex = i),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),

                // ── Content ─────────────────────────────────────────────────
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _searchActive
                        ? (_searchQuery.isEmpty
                            ? (history.isNotEmpty
                                ? _HistoryView(
                                    key: const ValueKey('history'),
                                    history: history,
                                    onUserTap: (u) => _onUserTap(u, context),
                                    onClear: () => ref
                                        .read(searchHistoryProvider.notifier)
                                        .clear(),
                                  )
                                : const _SearchHint(key: ValueKey('hint')))
                            : _UserResults(
                                key: const ValueKey('users'),
                                searchAsync: searchAsync,
                                scrollController: _scrollController,
                                onUserTap: (u) => _onUserTap(u, context),
                              ))
                        : _MemoriesFeed(
                            key: ValueKey('memories-$_tabIndex'),
                            memoriesAsync: memoriesAsync.whenData(
                              (list) => list
                                  .where(
                                    (m) => m.visibility ==
                                        (_tabIndex == 0
                                            ? MemoryVisibility.circle
                                            : MemoryVisibility.public),
                                  )
                                  .toList(),
                            ),
                            onRefresh: () =>
                                ref.read(discoverProvider.notifier).refresh(),
                            onLike: (id, liked) => ref
                                .read(discoverProvider.notifier)
                                .toggleLike(id, currentlyLiked: liked),
                            onCommentCountChanged: (id, delta) => ref
                                .read(discoverProvider.notifier)
                                .updateCommentCount(id, delta),
                            onMemoryTap: _onMemoryTap,
                            onAuthorTap: (author) =>
                                _onUserTap(author, context),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    required this.searchActive,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool searchActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: isDark ? 0.3 : 0.6),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onTap,
                  onChanged: onChanged,
                  style: AppTextStyles.body(context).copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Collegati a nuove persone',
                    hintStyle: AppTextStyles.bodySecondary(context)
                        .copyWith(fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (searchActive && controller.text.isNotEmpty) ...[
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ] else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User results ─────────────────────────────────────────────────────────────

class _UserResults extends StatelessWidget {
  const _UserResults({
    super.key,
    required this.searchAsync,
    required this.scrollController,
    required this.onUserTap,
  });

  final AsyncValue<UserSearchState> searchAsync;
  final ScrollController scrollController;
  final void Function(ProfileModel) onUserTap;

  @override
  Widget build(BuildContext context) {
    return searchAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Errore nel caricamento.\nRiprova.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySecondary(context),
        ),
      ),
      data: (s) {
        if (s.users.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_search_outlined,
                    size: 52, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  s.query.isEmpty
                      ? 'Nessun utente trovato\nnelle vicinanze'
                      : 'Nessun utente trovato\nper "${s.query}"',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySecondary(context),
                ),
              ],
            ),
          );
        }

        final itemCount = s.users.length + (s.hasMore ? 1 : 0);
        return ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            if (index == s.users.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _UserCard(
              user: s.users[index],
              onTap: () => onUserTap(s.users[index]),
            );
          },
        );
      },
    );
  }
}

// ─── Search hint (empty state) ────────────────────────────────────────────────

class _SearchHint extends StatelessWidget {
  const _SearchHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 52,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          Text(
            'Inizia a scrivere per trovare\npersone nella community',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySecondary(context),
          ),
        ],
      ),
    );
  }
}

// ─── History view ─────────────────────────────────────────────────────────────

class _HistoryView extends StatelessWidget {
  const _HistoryView({
    super.key,
    required this.history,
    required this.onUserTap,
    required this.onClear,
  });

  final List<ProfileModel> history;
  final void Function(ProfileModel) onUserTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: Row(
            children: [
              Text(
                'Recenti',
                style: AppTextStyles.bodySecondary(context).copyWith(
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Text(
                    'Cancella',
                    style: AppTextStyles.bodySecondary(context).copyWith(
                      fontSize: 12,
                      color: Colors.redAccent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
            itemCount: history.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _HistoryTile(
              user: history[i],
              onTap: () => onUserTap(history[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.user, required this.onTap});

  final ProfileModel user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        user.displayName.isNotEmpty ? user.displayName : user.username;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    const Color(0xFF7EB8D4).withValues(alpha: 0.25),
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7EB8D4),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body(context)
                          .copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${user.username}',
                      style: AppTextStyles.bodySecondary(context)
                          .copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.history_rounded,
                size: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User card ────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});

  final ProfileModel user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        user.displayName.isNotEmpty ? user.displayName : user.username;
    final initial = name.characters.first.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  const Color(0xFF7EB8D4).withValues(alpha: 0.25),
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7EB8D4),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Name + username + bio
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: AppTextStyles.bodySecondary(context)
                        .copyWith(fontSize: 12),
                  ),
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.bio,
                      style: AppTextStyles.bodySecondary(context)
                          .copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Distance + memories count
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (user.distanceKm != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.near_me_outlined,
                        size: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        user.distanceKm! < 1
                            ? '< 1 km'
                            : '${user.distanceKm!.toStringAsFixed(1)} km',
                        style: AppTextStyles.bodySecondary(context)
                            .copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bubble_chart_outlined,
                      size: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${user.memoriesCount}',
                      style: AppTextStyles.bodySecondary(context)
                          .copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ─── Memories feed ────────────────────────────────────────────────────────────

class _MemoriesFeed extends StatelessWidget {
  const _MemoriesFeed({
    super.key,
    required this.memoriesAsync,
    required this.onRefresh,
    required this.onLike,
    required this.onCommentCountChanged,
    required this.onMemoryTap,
    required this.onAuthorTap,
  });

  final AsyncValue<List<MemoryModel>> memoriesAsync;
  final Future<void> Function() onRefresh;
  final void Function(String id, bool currentlyLiked) onLike;
  final void Function(String id, int delta) onCommentCountChanged;
  final void Function(MemoryModel) onMemoryTap;
  final void Function(ProfileModel) onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return memoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              'Impossibile caricare i ricordi.\nControlla la connessione.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary(context),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRefresh,
              child: const Text('Riprova'),
            ),
          ],
        ),
      ),
      data: (memories) {
        if (memories.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_outlined,
                    size: 56, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  'Nessun ricordo ancora.\nSii il primo a lasciarne uno!',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySecondary(context),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
            itemCount: memories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 20),
            itemBuilder: (context, index) => _MemoryCard(
              memory: memories[index],
              onLike: () => onLike(memories[index].id, memories[index].isLikedByMe),
              onCommentCountChanged: (delta) =>
                  onCommentCountChanged(memories[index].id, delta),
              onTap: () => onMemoryTap(memories[index]),
              onAuthorTap: onAuthorTap,
            ),
          ),
        );
      },
    );
  }
}

// ─── Memory card ──────────────────────────────────────────────────────────────

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({
    required this.memory,
    required this.onLike,
    required this.onCommentCountChanged,
    required this.onTap,
    required this.onAuthorTap,
  });

  final MemoryModel memory;
  final VoidCallback onLike;
  final void Function(int delta) onCommentCountChanged;
  final VoidCallback onTap;
  final void Function(ProfileModel) onAuthorTap;

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final currentUserId = ref.read(currentUserProvider)?.id ?? '';
    final isOwn = currentUserId == memory.userId;

    final action = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        if (isOwn)
          const AdaptiveAction(
            value: 'delete',
            label: 'Elimina ricordo',
            icon: Icons.delete_outline,
            isDestructive: true,
          ),
        const AdaptiveAction(
          value: 'report',
          label: 'Segnala post',
          icon: Icons.flag_outlined,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') _confirmDelete(context, ref);
    if (action == 'report') _confirmReport(context, ref);
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina ricordo',
      message: 'Sei sicuro di voler eliminare questo ricordo? L\'azione non è reversibile.',
      confirmLabel: 'Elimina',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).deleteMemory(memory.id);
      ref.invalidate(discoverProvider);
      if (context.mounted) {
        EchoToast.show(context, 'Ricordo eliminato.', type: EchoToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  void _confirmReport(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Segnala post',
      message: 'Sei sicuro di voler segnalare questo contenuto? Lo esamineremo quanto prima.',
      confirmLabel: 'Segnala',
      cancelLabel: 'Annulla',
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).reportMemory(memory.id);
      if (context.mounted) {
        EchoToast.show(context, 'Segnalazione inviata. Grazie.', type: EchoToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        EchoToast.show(context, 'Errore: $e', type: EchoToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (memory.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: CachedNetworkImage(
                imageUrl: memory.imageUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(height: 180, color: Colors.white10),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MoodBadge(mood: memory.mood),
                    const Spacer(),
                    if (memory.author != null)
                      _AuthorChip(
                        author: memory.author!,
                        onTap: () => onAuthorTap(memory.author!),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  memory.description,
                  style: AppTextStyles.body(context),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                // TODO: AI v2 — aiCaption rimossa dalla card
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (memory.locationName != null) ...[
                      Icon(Icons.location_on_outlined,
                          size: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          memory.locationName!,
                          style: AppTextStyles.bodySecondary(context)
                              .copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      timeago.format(memory.createdAt, locale: 'it'),
                      style: AppTextStyles.bodySecondary(context)
                          .copyWith(fontSize: 12),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => showCommentsSheet(
                        context,
                        memory.id,
                        onCommentCountChanged: onCommentCountChanged,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 17,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.35),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${memory.commentsCount}',
                            style: AppTextStyles.bodySecondary(context)
                                .copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: onLike,
                      child: Row(
                        children: [
                          Icon(
                            memory.isLikedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: memory.isLikedByMe
                                ? const Color(0xFFE8879C)
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${memory.likesCount}',
                            style: AppTextStyles.bodySecondary(context)
                                .copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _showOptions(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.ellipsis
                              : Icons.more_horiz_rounded,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Mood badge ───────────────────────────────────────────────────────────────

class _MoodBadge extends StatelessWidget {
  const _MoodBadge({required this.mood});
  final MemoryMood mood;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mood.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mood.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        mood.label,
        style: TextStyle(
          fontSize: 12,
          color: mood.color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Author chip ──────────────────────────────────────────────────────────────

class _AuthorChip extends StatelessWidget {
  const _AuthorChip({required this.author, required this.onTap});
  final ProfileModel author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF7EB8D4).withValues(alpha: 0.3),
          backgroundImage: author.avatarUrl != null
              ? CachedNetworkImageProvider(author.avatarUrl!)
              : null,
          child: author.avatarUrl == null
              ? Text(
                  (author.displayName.isNotEmpty
                          ? author.displayName
                          : author.username)
                      .characters
                      .first
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7EB8D4),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          '@${author.username}',
          style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 12),
        ),
      ],
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

// ─── Discover tab row ─────────────────────────────────────────────────────────

class _DiscoverTabRow extends StatelessWidget {
  const _DiscoverTabRow({required this.tabIndex, required this.onChanged});
  final int tabIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DiscoverTabChip(
          label: 'Cerchia',
          icon: Icons.people_outline,
          selected: tabIndex == 0,
          onTap: () => onChanged(0),
        ),
        const SizedBox(width: 8),
        _DiscoverTabChip(
          label: 'Pubblici',
          icon: Icons.public_outlined,
          selected: tabIndex == 1,
          onTap: () => onChanged(1),
        ),
      ],
    );
  }
}

class _DiscoverTabChip extends StatelessWidget {
  const _DiscoverTabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isDark
              ? (selected
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05))
              : (selected
                  ? primary.withValues(alpha: 0.12)
                  : onSurface.withValues(alpha: 0.06)),
          border: Border.all(
            color: isDark
                ? (selected
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.1))
                : (selected
                    ? primary.withValues(alpha: 0.5)
                    : onSurface.withValues(alpha: 0.12)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isDark
                  ? (selected ? Colors.white : Colors.white54)
                  : (selected ? primary : onSurface.withValues(alpha: 0.5)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: isDark
                    ? (selected ? Colors.white : Colors.white54)
                    : (selected ? primary : onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF100F1C), Color(0xFF181528), Color(0xFF100E1A)]
              : const [Color(0xFFF3F1FC), Color(0xFFE9E6F7), Color(0xFFF8F9FB)],
        ),
      ),
    );
  }
}
