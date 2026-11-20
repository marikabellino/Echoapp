import 'package:echo/features/drop/presentation/widgets/relation_badge.dart';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/services/location_service.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/brand/mingle_dot.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/core/services/drop_image_signer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timeago/timeago.dart' as timeago;

class StoryGroup {
  StoryGroup(this.author, this.drops);
  final ProfileModel author;
  final List<DropModel> drops;

  bool get isFresh =>
      DateTime.now().difference(drops.first.createdAt) <
      const Duration(hours: 24);
}

final circleStoriesProvider = Provider.autoDispose<List<StoryGroup>>((ref) {
  final me = ref.watch(currentUserProvider)?.id;
  final circle = ref.watch(myConnectionsProvider).asData?.value ?? const [];
  final drops = ref.watch(discoverProvider).asData?.value ?? const [];
  final circleIds = circle.map((p) => p.id).toSet();
  final byAuthor = <String, List<DropModel>>{};
  for (final d in drops) {
    if (d.userId == me || !circleIds.contains(d.userId)) continue;
    byAuthor.putIfAbsent(d.userId, () => []).add(d);
  }
  final groups = <StoryGroup>[];
  for (final entry in byAuthor.entries) {
    final list = entry.value
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final author =
        list.first.author ?? circle.firstWhere((p) => p.id == entry.key);
    groups.add(StoryGroup(author, list));
  }
  groups.sort(
    (a, b) => b.drops.first.createdAt.compareTo(a.drops.first.createdAt),
  );
  return groups;
});

class CircleStoriesRow extends ConsumerWidget {
  const CircleStoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(circleStoriesProvider);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: groups.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _StoryBubble(
              label: 'Il tuo drop',
              ring: false,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(shellIndexProvider.notifier).setIndex(2);
              },
              child: Container(
                color: AppColors.darkSurfaceLight,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            );
          }
          final g = groups[i - 1];
          final avatar = g.author.avatarUrl;
          return _StoryBubble(
                label: g.author.username,
                ring: true,
                fresh: g.isFresh,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      transitionDuration: const Duration(milliseconds: 280),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 220,
                      ),
                      pageBuilder: (_, _, _) =>
                          StoryViewerPage(groups: groups, initialGroup: i - 1),
                      transitionsBuilder: (_, a, _, child) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.94, end: 1.0).animate(
                            CurvedAnimation(parent: a, curve: Curves.easeOut),
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: avatar != null && avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            _InitialAvatar(name: g.author.username),
                      )
                    : _InitialAvatar(name: g.author.username),
              )
              .animate(delay: (50 * i).ms)
              .fadeIn(duration: 300.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                duration: 380.ms,
                curve: Curves.easeOutBack,
              );
        },
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.label,
    required this.child,
    required this.onTap,
    required this.ring,
    this.fresh = false,
  });

  final String label;
  final Widget child;
  final VoidCallback onTap;
  final bool ring;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ring && fresh ? AppColors.accent : null,
                border: ring && !fresh
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      )
                    : !ring
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkBackground,
                ),
                child: ClipOval(child: child),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.groups,
    required this.initialGroup,
  });

  final List<StoryGroup> groups;
  final int initialGroup;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with SingleTickerProviderStateMixin {
  late int _group = widget.initialGroup;
  int _index = 0;
  double _dragY = 0;
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });

  StoryGroup get _current => widget.groups[_group];
  DropModel get _drop => _current.drops[_index];

  @override
  void initState() {
    super.initState();
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _restart() {
    _progress
      ..reset()
      ..forward();
  }

  void _next() {
    if (_index < _current.drops.length - 1) {
      setState(() => _index++);
    } else if (_group < widget.groups.length - 1) {
      setState(() {
        _group++;
        _index = 0;
      });
    } else {
      Navigator.of(context).maybePop();
      return;
    }
    _restart();
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    } else if (_group > 0) {
      setState(() {
        _group--;
        _index = widget.groups[_group].drops.length - 1;
      });
    }
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final drop = _drop;
    final author = _current.author;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final dismiss = (_dragY / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - dismiss),
      body: GestureDetector(
        onTapUp: (d) => d.localPosition.dx < width / 3 ? _prev() : _next(),
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        onVerticalDragUpdate: (d) {
          _progress.stop();
          setState(() => _dragY = (_dragY + d.delta.dy).clamp(0, 600));
        },
        onVerticalDragEnd: (d) {
          if (_dragY > 140 || (d.primaryVelocity ?? 0) > 800) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragY = 0);
            _progress.forward();
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragY),
          child: Transform.scale(
            scale: 1 - dismiss * 0.12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(dismiss > 0 ? 28 : 0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: drop.imageUrl != null && drop.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            key: ValueKey(drop.id),
                            imageUrl: drop.imageUrl!,
                            cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                const ColoredBox(color: AppColors.darkSurface),
                            errorWidget: (_, _, _) => _TextStory(drop: drop),
                          )
                        : _TextStory(key: ValueKey(drop.id), drop: drop),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.2, 0.65, 1.0],
                        colors: [
                          Color(0x99000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xCC000000),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: top + 8,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < _current.drops.length; i++) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: SizedBox(
                                    height: 3,
                                    child: i == _index
                                        ? AnimatedBuilder(
                                            animation: _progress,
                                            builder: (_, _) =>
                                                LinearProgressIndicator(
                                                  value: _progress.value,
                                                  backgroundColor: Colors.white
                                                      .withValues(alpha: 0.3),
                                                  color: Colors.white,
                                                ),
                                          )
                                        : ColoredBox(
                                            color: Colors.white.withValues(
                                              alpha: i < _index ? 1 : 0.3,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: AppColors.darkSurfaceLight,
                              backgroundImage: author.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      author.avatarUrl!,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    author.username,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    [
                                      timeago.format(
                                        drop.createdAt,
                                        locale: 'it',
                                      ),
                                      ?drop.displayLocation,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: bottom + 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (drop.description.isNotEmpty &&
                            (drop.imageUrl?.isNotEmpty ?? false))
                          Text(
                            drop.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            _progress.stop();
                            openDropDetail(
                              context,
                              drop,
                            ).then((_) => _progress.forward());
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Apri il drop',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

typedef _NearbyDrop = ({DropModel drop, double meters});
const double _nearbyCardRadius = 1500;

final _nearbyForDiscoverProvider =
    FutureProvider.autoDispose<List<_NearbyDrop>>((ref) async {
      final pos = await ref.watch(userPositionProvider.future);
      if (pos == null) return const [];
      final me = ref.watch(currentUserProvider)?.id;
      final drops = await ref.watch(
        nearbyDropsProvider((lat: pos.latitude, lng: pos.longitude)).future,
      );
      return [
        for (final d in drops)
          if (d.userId != me)
            (
              drop: d,
              meters: Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                d.latitude,
                d.longitude,
              ),
            ),
      ]..sort((a, b) => a.meters.compareTo(b.meters));
    });

/// "Vicino a te": compare a card solo quando c'è qualcosa davvero a portata
/// di passeggiata (entro [_nearbyCardRadius]). Quelli ancora chiusi mostrano
/// un Dot che sbircia, la distanza e un anello che si riempie man mano che ti
/// avvicini; quelli entro il raggio di scoperta sono aperti. Se intorno c'è
/// solo roba lontana, resta una riga compatta che porta alla mappa.
class NearbyLockedSection extends ConsumerWidget {
  const NearbyLockedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(_nearbyForDiscoverProvider).asData?.value;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final nearby = all
        .where((n) => n.meters <= _nearbyCardRadius)
        .take(12)
        .toList();
    if (nearby.isEmpty) return _FarDropsRow(count: all.length);
    final open = nearby
        .where((n) => n.meters <= DropModel.discoveryRadius)
        .length;
    final locked = nearby.length - open;
    final title = open > 0
        ? (open == 1 ? '1 drop da aprire' : '$open drop da aprire')
        : (locked == 1 ? '1 drop da scovare' : '$locked drop da scovare');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VICINO A TE', style: AppTextStyles.eyebrow(context)),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: AppTextStyles.headline(
                        context,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(shellIndexProvider.notifier).setIndex(1);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: const Text(
                  'Mappa',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: nearby.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _NearbyCard(item: nearby[i])
                .animate(delay: (60 * i).ms)
                .fadeIn(duration: 320.ms)
                .scale(
                  begin: const Offset(.9, .9),
                  duration: 420.ms,
                  curve: Curves.easeOutBack,
                ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Niente a portata di passeggiata: una riga sola che dice quanti drop ci
/// sono nei dintorni e porta alla mappa, senza occupare mezza schermata.
class _FarDropsRow extends ConsumerWidget {
  const _FarDropsRow({required this.count});
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = count == 1
        ? '1 drop nei dintorni'
        : '$count drop nei dintorni';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Material(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(shellIndexProvider.notifier).setIndex(1);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                const MingleDot(size: 34, face: DotFace.wink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.paper,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Il più vicino è a più di 1,5 km',
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Mappa',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyCard extends ConsumerWidget {
  const _NearbyCard({required this.item});
  final _NearbyDrop item;

  String get _distance => item.meters < 1000
      ? '${item.meters.round()} m'
      : '${(item.meters / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drop = item.drop;
    final locked = item.meters > DropModel.discoveryRadius;
    // 0 = al bordo della sezione (1,5 km), 1 = sei nel raggio di scoperta.
    final closeness =
        (1 -
                (item.meters - DropModel.discoveryRadius) /
                    (_nearbyCardRadius - DropModel.discoveryRadius))
            .clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () {
        if (locked) {
          HapticFeedback.mediumImpact();
          EchoToast.show(
            context,
            'Avvicinati a meno di ${DropModel.discoveryRadius.round()} m per aprirlo',
          );
          ref.read(mapFlyTargetProvider.notifier).set(drop);
          ref.read(shellIndexProvider.notifier).setIndex(1);
        } else {
          openDropDetail(context, drop);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          width: 148,
          child: locked
              ? _lockedBody(context, drop, closeness)
              : _openBody(context, drop),
        ),
      ),
    );
  }

  Widget _lockedBody(BuildContext context, DropModel drop, double closeness) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.darkSurface),
        // La foto si intravede appena: è un indizio, non uno spoiler.
        if (drop.imageUrl != null)
          Opacity(
            opacity: .28,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: CachedNetworkImage(
                imageUrl: drop.imageUrl!,
                cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
                fit: BoxFit.cover,
                memCacheWidth: 120,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderDark),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: closeness,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        color: AppColors.accent,
                        backgroundColor: AppColors.darkSurfaceHigh,
                      ),
                    ),
                    const MingleDot(size: 52, face: DotFace.wink),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _distance,
                style: AppTextStyles.displayLarge(
                  context,
                ).copyWith(fontSize: 24, color: AppColors.paper),
              ),
              const SizedBox(height: 2),
              Text(
                drop.displayLocation ?? 'da scovare',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySecondary(
                  context,
                ).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _openBody(BuildContext context, DropModel drop) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (drop.imageUrl != null)
          CachedNetworkImage(
            imageUrl: drop.imageUrl!,
            cacheKey: DropImageSigner.cacheKey(drop.imageUrl!),
            fit: BoxFit.cover,
            memCacheWidth: 360,
            placeholder: (_, _) =>
                const ColoredBox(color: AppColors.darkSurfaceLight),
          )
        else
          const DropPlaceholder(),
        // Velo in basso solo per leggere il testo sulla foto.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.55, 1.0],
              colors: [Color(0x00000000), Color(0xB30D0B0E)],
            ),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              'Qui!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const Positioned(
          top: 6,
          right: 6,
          child: MingleDot(size: 34, face: DotFace.love),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Text(
            drop.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TextStory extends StatelessWidget {
  const _TextStory({super.key, required this.drop});
  final DropModel drop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent,
            Color.lerp(AppColors.accent, AppColors.darkBackground, 0.7)!,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.format_quote_rounded,
                size: 36,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              Text(
                drop.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
