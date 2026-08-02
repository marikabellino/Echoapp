import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/drop/presentation/widgets/drop_feed_card.dart';
import 'package:echo/features/events/domain/models/event_model.dart';
import 'package:echo/features/events/providers/events_provider.dart';
import 'package:echo/features/map/presentation/pages/create_page.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dropsAsync = ref.watch(eventDropsProvider(event.id));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (isDark)
            const AnimatedGradientBackground(child: SizedBox.expand())
          else
            const ColoredBox(
              color: AppColors.lightBackground,
              child: SizedBox.expand(),
            ),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: isDark
                  ? AppColors.darkSurface
                  : AppColors.lightSurface,
              elevation: 0,
              edgeOffset: 64,
              onRefresh: () => ref.refresh(eventDropsProvider(event.id).future),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: CollapsingGlassHeaderDelegate(
                      isDark: isDark,
                      minExtent: 64,
                      maxExtent: 176,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      pinnedGap: 12,
                      pinned: (context) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GlassIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          GlassIconButton(
                            icon: Icons.add_rounded,
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CreatePage(initialEvent: event),
                                ),
                              );
                              ref.invalidate(eventDropsProvider(event.id));
                            },
                          ),
                        ],
                      ),
                      dissolving: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.title,
                            style: AppTextStyles.displayLarge(
                              context,
                            ).copyWith(fontSize: 24),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event.venueName,
                            style: AppTextStyles.bodySecondary(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  dropsAsync.when(
                    loading: () => const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'Impossibile caricare i ricordi di questo evento.',
                          style: AppTextStyles.bodySecondary(context),
                        ),
                      ),
                    ),
                    data: (drops) {
                      if (drops.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'Nessun ricordo ancora per questo evento.',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final drop = drops[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: DropCard(
                                drop: drop,
                                onLike: () async {
                                  await ref
                                      .read(dropRepositoryProvider)
                                      .toggleLike(
                                        drop.id,
                                        isLiked: drop.isLikedByMe,
                                      );
                                  ref.invalidate(likersProvider(drop.id));
                                  ref.invalidate(eventDropsProvider(event.id));
                                },
                                onCommentCountChanged: (_) => ref.invalidate(
                                  eventDropsProvider(event.id),
                                ),
                                onTap: () {},
                                onAuthorTap: (author) =>
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfilePage(user: author),
                                      ),
                                    ),
                              ),
                            );
                          }, childCount: drops.length),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Event card (used in the Eventi tab list) ────────────────────────────────

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});
  final EventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusLabel = event.isLive
        ? 'In corso'
        : 'Terminato ${timeago.format(event.endsAt, locale: 'it')}';

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
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
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentSecondary.withValues(alpha: 0.15),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.event_outlined,
                    color: AppColors.accentSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${event.venueName} · ${event.city}',
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: event.isLive
                              ? AppColors.accentSecondary
                              : AppTextStyles.bodySecondary(context).color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.accentSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
