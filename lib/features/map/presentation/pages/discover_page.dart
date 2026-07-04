import 'dart:async';
import 'dart:ui';

import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/services/location_service.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/community/providers/user_search_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/presentation/widgets/drop_feed_card.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/events/presentation/pages/event_detail_page.dart';
import 'package:echo/features/events/providers/events_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:echo/shared/widgets/skeleton_loader.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _feedScrollController = ScrollController();
  Timer? _debounce;
  bool _searchActive = false;
  String _searchQuery = '';
  int _tabIndex = 0; // 0 = Cerchia, 1 = Pubblici, 2 = Eventi

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

  // Riporta la pagina allo stato iniziale (tab Cerchia, ricerca chiusa)
  // quando l'utente naviga via da Scopri, così la ritrova pulita al rientro.
  void _resetOnLeave() {
    _focusNode.unfocus();
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
      _tabIndex = 0;
    });
    ref.read(userSearchProvider.notifier).reset();
  }

  void _onUserTap(ProfileModel user, BuildContext context) {
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (user.id == currentUserId) {
      // È il proprio profilo — passa al tab Profilo invece di aprire
      // UserProfilePage, così la navbar resta visibile.
      ref.read(shellIndexProvider.notifier).setIndex(4);
      return;
    }
    ref.read(searchHistoryProvider.notifier).add(user);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserProfilePage(user: user)));
  }

  void _onDropTap(DropModel drop) {
    ref.read(mapFlyTargetProvider.notifier).set(drop);
    ref.read(shellIndexProvider.notifier).setIndex(1);
  }

  void _scrollFeedToTop() {
    if (!_feedScrollController.hasClients) return;
    _feedScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _feedScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scopri è l'indice 0 nella shell: appena l'utente passa a un'altra
    // tab, azzeriamo lo stato locale (tab attiva, ricerca) per il rientro.
    ref.listen<int>(shellIndexProvider, (prev, next) {
      if (prev == 0 && next != 0) _resetOnLeave();
    });

    // Tap sull'icona "Scopri" già attiva nella navbar → se si sta cercando,
    // chiude la ricerca e torna al feed; altrimenti scrolla in cima.
    ref.listen(tabRetapProvider, (prev, next) {
      if (next?.index != 0) return;
      if (_searchActive) {
        _closeSearch();
      } else {
        _scrollFeedToTop();
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final dropsAsync = ref.watch(discoverProvider);
    final searchAsync = ref.watch(userSearchProvider);
    final history = ref.watch(searchHistoryProvider);
    final connectionIds =
        ref
            .watch(myConnectionsProvider)
            .asData
            ?.value
            .map((u) => u.id)
            .toSet() ??
        const <String>{};

    if (!isOnline) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
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
                      'Drop lasciati nel mondo',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                  ],
                ),
              ),
            ),
            const OfflinePlaceholder(
              message: 'Cerca persone e drop non è disponibile offline.',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _searchActive
                  ? KeyedSubtree(
                      key: const ValueKey('search'),
                      child: _buildSearchBody(
                        context,
                        isDark,
                        history,
                        searchAsync,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('feed'),
                      child: _buildFeedBody(
                        context,
                        isDark,
                        dropsAsync,
                        connectionIds,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search mode: static header (title + Annulla + search bar) ──────────
  Widget _buildSearchBody(
    BuildContext context,
    bool isDark,
    List<ProfileModel> history,
    AsyncValue<UserSearchState> searchAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Scopri', style: AppTextStyles.displayLarge(context)),
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: GestureDetector(
                        onTap: _closeSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : Colors.black.withValues(alpha: 0.10),
                              width: 0.75,
                            ),
                          ),
                          child: Text(
                            'Annulla',
                            style: AppTextStyles.bodySecondary(
                              context,
                            ).copyWith(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Trova persone nella community',
                  style: AppTextStyles.bodySecondary(context),
                ),
              ),
              const SizedBox(height: 16),
              _SearchBar(
                controller: _searchController,
                focusNode: _focusNode,
                onTap: _activateSearch,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  ref.read(userSearchProvider.notifier).search('');
                },
                searchActive: true,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _searchQuery.isEmpty
                ? (history.isNotEmpty
                      ? _HistoryView(
                          key: const ValueKey('history'),
                          history: history,
                          onUserTap: (u) => _onUserTap(u, context),
                          onClear: () =>
                              ref.read(searchHistoryProvider.notifier).clear(),
                        )
                      : const _SearchHint(key: ValueKey('hint')))
                : _UserResults(
                    key: const ValueKey('users'),
                    searchAsync: searchAsync,
                    scrollController: _scrollController,
                    onUserTap: (u) => _onUserTap(u, context),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Feed mode: header collapses/dissolves into a pinned glass bar ───────
  Widget _buildFeedBody(
    BuildContext context,
    bool isDark,
    AsyncValue<List<DropModel>> dropsAsync,
    Set<String> connectionIds,
  ) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      elevation: 0,
      // Fa comparire lo spinner sotto l'intestazione (titolo + ricerca +
      // chip) invece che sopra di essa, allineandolo all'altezza massima
      // dell'header collassabile.
      edgeOffset: 234,
      onRefresh: () => ref.read(discoverProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _feedScrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingGlassHeaderDelegate(
              isDark: isDark,
              minExtent: 72,
              maxExtent: 234,
              pinned: (context) =>
                  Text('Scopri', style: AppTextStyles.displayLarge(context)),
              dissolving: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drop lasciati nel mondo',
                    style: AppTextStyles.bodySecondary(context),
                  ),
                  const SizedBox(height: 16),
                  _SearchBar(
                    controller: _searchController,
                    focusNode: _focusNode,
                    onTap: _activateSearch,
                    onChanged: _onSearchChanged,
                    searchActive: false,
                  ),
                  const SizedBox(height: 12),
                  _DiscoverTabRow(
                    tabIndex: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                ],
              ),
            ),
          ),
          if (_tabIndex == 2)
            const _EventsFeed()
          else
            _DropsFeed(
              key: ValueKey('drops-$_tabIndex'),
              dropsAsync: dropsAsync.whenData(
                (list) => list.where((m) {
                  if (_tabIndex == 0) {
                    // Cerchia: drop riservati alla cerchia + drop pubblici
                    // di persone che segui.
                    return m.visibility == DropVisibility.circle ||
                        (m.visibility == DropVisibility.public &&
                            connectionIds.contains(m.userId));
                  }
                  return m.visibility == DropVisibility.public;
                }).toList(),
              ),
              onRetry: () => ref.read(discoverProvider.notifier).refresh(),
              onLike: (id, liked) => ref
                  .read(discoverProvider.notifier)
                  .toggleLike(id, currentlyLiked: liked),
              onCommentCountChanged: (id, delta) => ref
                  .read(discoverProvider.notifier)
                  .updateCommentCount(id, delta),
              onDropTap: _onDropTap,
              onAuthorTap: (author) => _onUserTap(author, context),
            ),
        ],
      ),
    );
  }
}

// ─── Eventi ────────────────────────────────────────────────────────────────────

class _EventsFeed extends ConsumerWidget {
  const _EventsFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(userPositionProvider);

    return positionAsync.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyEvents(
          message: 'Non riusciamo a rilevare la tua posizione.',
          onRetry: () => ref.invalidate(userPositionProvider),
        ),
      ),
      data: (position) {
        if (position == null) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyEvents(
              message: 'Attiva la posizione per vedere gli eventi vicino a te.',
              onRetry: () => ref.invalidate(userPositionProvider),
            ),
          );
        }

        final eventsAsync = ref.watch(
          nearbyActiveEventsProvider((
            lat: position.latitude,
            lng: position.longitude,
          )),
        );

        return eventsAsync.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyEvents(message: 'Impossibile caricare gli eventi.'),
          ),
          data: (events) {
            if (events.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyEvents(
                  message: 'Nessun evento disponibile vicino a te.',
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EventCard(
                      event: events[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDetailPage(event: events[i]),
                        ),
                      ),
                    ),
                  ),
                  childCount: events.length,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined, size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySecondary(context),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
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
        child: AnimatedBuilder(
          animation: focusNode,
          builder: (context, child) {
            final hasFocus = focusNode.hasFocus;
            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: isDark ? 0.3 : 0.6),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: hasFocus
                      ? AppColors.accentSecondary
                      : (isDark
                            ? Theme.of(context).dividerColor
                            : Colors.black.withValues(alpha: 0.12)),
                  width: hasFocus ? 1.5 : 1,
                ),
              ),
              child: child,
            );
          },
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onTap,
                  onChanged: onChanged,
                  textAlignVertical: TextAlignVertical.center,
                  style: AppTextStyles.body(context).copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Collegati a nuove persone',
                    hintStyle: AppTextStyles.bodySecondary(
                      context,
                    ).copyWith(fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
      loading: () => const SkeletonSearchUserList(),
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
                const Icon(
                  Icons.person_search_outlined,
                  size: 52,
                  color: Colors.white24,
                ),
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.18),
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
                style: AppTextStyles.bodySecondary(
                  context,
                ).copyWith(fontSize: 12, letterSpacing: 0.5),
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
                    borderRadius: BorderRadius.circular(AppRadius.pill),
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
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
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
                      style: AppTextStyles.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${user.username}',
                      style: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.history_rounded,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.25),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    final initial = name.characters.first.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.55)
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                    backgroundImage: user.avatarUrl != null
                        ? CachedNetworkImageProvider(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
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
                          style: AppTextStyles.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user.username}',
                          style: AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(fontSize: 12),
                        ),
                        if (user.bio.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            user.bio,
                            style: AppTextStyles.bodySecondary(
                              context,
                            ).copyWith(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Distance + drops count
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
                              style: AppTextStyles.bodySecondary(
                                context,
                              ).copyWith(fontSize: 11),
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
                            '${user.dropsCount}',
                            style: AppTextStyles.bodySecondary(
                              context,
                            ).copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Drops feed ────────────────────────────────────────────────────────────

class _DropsFeed extends StatelessWidget {
  const _DropsFeed({
    super.key,
    required this.dropsAsync,
    required this.onRetry,
    required this.onLike,
    required this.onCommentCountChanged,
    required this.onDropTap,
    required this.onAuthorTap,
  });

  final AsyncValue<List<DropModel>> dropsAsync;
  final VoidCallback onRetry;
  final void Function(String id, bool currentlyLiked) onLike;
  final void Function(String id, int delta) onCommentCountChanged;
  final void Function(DropModel) onDropTap;
  final void Function(ProfileModel) onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return dropsAsync.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: SkeletonDropFeed(),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Colors.white30,
              ),
              const SizedBox(height: 16),
              Text(
                'Impossibile caricare i drop.\nControlla la connessione.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary(context),
              ),
              const SizedBox(height: 20),
              TextButton(onPressed: onRetry, child: const Text('Riprova')),
            ],
          ),
        ),
      ),
      data: (drops) {
        if (drops.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.explore_outlined,
                    size: 56,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun drop ancora.\nSii il primo a lasciarne uno!',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary(context),
                  ),
                ],
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: DropCard(
                  drop: drops[index],
                  onLike: () =>
                      onLike(drops[index].id, drops[index].isLikedByMe),
                  onCommentCountChanged: (delta) =>
                      onCommentCountChanged(drops[index].id, delta),
                  onTap: () => onDropTap(drops[index]),
                  onAuthorTap: onAuthorTap,
                ),
              ),
              childCount: drops.length,
            ),
          ),
        );
      },
    );
  }
}

// ─── Drop card ──────────────────────────────────────────────────────────────

// _DropCard, MoodBadge, AuthorChip, CircleAction, MoodGradientBackground
// sono stati spostati in drop_feed_card.dart per essere riusati anche
// dalla pagina di dettaglio evento.

// ─── Background ───────────────────────────────────────────────────────────────

// ─── Discover tab row ─────────────────────────────────────────────────────────

class _DiscoverTabRow extends StatelessWidget {
  const _DiscoverTabRow({required this.tabIndex, required this.onChanged});
  final int tabIndex;
  final ValueChanged<int> onChanged;

  static const _tabCount = 3;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        void updateFromLocalX(double dx) {
          final index = (dx / constraints.maxWidth * _tabCount).floor().clamp(
            0,
            _tabCount - 1,
          );
          if (index != tabIndex) onChanged(index);
        }

        return GestureDetector(
          onPanUpdate: (details) => updateFromLocalX(details.localPosition.dx),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(
                        _tabCount > 1 ? 2 * tabIndex / (_tabCount - 1) - 1 : 0,
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / _tabCount,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.accent,
                                  AppColors.accentSecondary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _DiscoverTabSegment(
                              label: 'Cerchia',
                              icon: Icons.people_outline,
                              selected: tabIndex == 0,
                              onTap: () => onChanged(0),
                            ),
                          ),
                          Expanded(
                            child: _DiscoverTabSegment(
                              label: 'Pubblici',
                              icon: Icons.public_outlined,
                              selected: tabIndex == 1,
                              onTap: () => onChanged(1),
                            ),
                          ),
                          Expanded(
                            child: _DiscoverTabSegment(
                              label: 'Eventi',
                              icon: Icons.event_outlined,
                              selected: tabIndex == 2,
                              onTap: () => onChanged(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DiscoverTabSegment extends StatelessWidget {
  const _DiscoverTabSegment({
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mutedColor = onSurface.withValues(alpha: 0.55);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : mutedColor),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : mutedColor,
              ),
              child: Text(label),
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
    if (isDark) {
      return const AnimatedGradientBackground(child: SizedBox.expand());
    }
    return Container(
      decoration: const BoxDecoration(color: AppColors.lightBackground),
    );
  }
}
