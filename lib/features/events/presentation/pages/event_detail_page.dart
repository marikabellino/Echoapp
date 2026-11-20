import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/age_provider.dart';
import 'package:echo/features/community/presentation/pages/user_profile_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/drop/presentation/widgets/drop_feed_card.dart';
import 'package:echo/features/events/domain/models/event_model.dart';
import 'package:echo/features/events/providers/events_provider.dart';
import 'package:echo/features/map/presentation/pages/create_page.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
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
    final minor = ref.watch(isMinorProvider).asData?.value ?? false;

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
                          // Si aggiungono drop solo durante l'evento (e
                          // mai sotto i 18 anni a un evento 18+).
                          if (event.isLive && !(minor && event.adultsOnly))
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
                            event.isLive
                                ? '● LIVE ORA'
                                : event.hasEnded
                                ? 'SERATA FINITA · I RICORDI'
                                : 'IN ARRIVO',
                            style: AppTextStyles.eyebrow(context).copyWith(
                              color: event.isLive
                                  ? AppColors.accent
                                  : AppColors.accentSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
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
                  if (minor || event.adultsOnly)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _AgeNotice(
                          adultsOnly: event.adultsOnly,
                          minor: minor,
                        ),
                      ),
                    ),
                  dropsAsync.when(
                    loading: () => const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: MingleLoader()),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PartyDot(size: 190),
                                const SizedBox(height: 12),
                                Text(
                                  event.hasEnded
                                      ? 'Nessun ricordo per questa serata.'
                                      : event.isLive
                                      ? 'La serata è appena iniziata.\nLascia tu il primo drop!'
                                      : 'La serata non è ancora iniziata.\nTorna qui quando parte!',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodySecondary(context),
                                ),
                              ],
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

/// Card evento a forma di biglietto (stile Dice): copertina, data grande,
/// chip LIVE, fustellatura e Dot festaiolo quando manca la foto.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});
  final EventModel event;
  final VoidCallback onTap;

  static const _months = [
    'GEN',
    'FEB',
    'MAR',
    'APR',
    'MAG',
    'GIU',
    'LUG',
    'AGO',
    'SET',
    'OTT',
    'NOV',
    'DIC',
  ];

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final upcoming = !event.isLive && !event.hasEnded;
    final status = event.isLive
        ? 'LIVE'
        : upcoming
        ? '${timeago.format(event.startsAt, locale: 'it', allowFromNow: true).toUpperCase()}'
        : 'FINITO';
    final cover = event.coverImageUrl;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ColoredBox(
          color: AppColors.darkSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Copertina ────────────────────────────────────────────
              SizedBox(
                height: 168,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const ColoredBox(color: AppColors.darkSurfaceLight),
                        errorWidget: (_, _, _) => const _EventPoster(),
                      )
                    else
                      const _EventPoster(),
                    if (cover != null)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    // Data
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${start.day}',
                              style: AppTextStyles.displayLarge(context)
                                  .copyWith(
                                    fontSize: 24,
                                    color: AppColors.ink,
                                    height: 1,
                                  ),
                            ),
                            Text(
                              _months[start.month - 1],
                              style: AppTextStyles.eyebrow(
                                context,
                              ).copyWith(color: AppColors.ink, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Stato
                    Positioned(
                      top: 14,
                      right: 12,
                      child: _StatusChip(label: status, live: event.isLive),
                    ),
                  ],
                ),
              ),

              // ── Fustellatura del biglietto ───────────────────────────
              const _Perforation(),

              // ── Info ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 14, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: AppTextStyles.headline(context).copyWith(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${event.venueName} · ${event.city}',
                            style: AppTextStyles.bodySecondary(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_hhmm(start)} – ${_hhmm(end)}',
                            style: AppTextStyles.eyebrow(
                              context,
                            ).copyWith(color: AppColors.accentSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: event.hasEnded
                            ? AppColors.darkSurfaceHigh
                            : AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        event.hasEnded ? 'Drop della serata' : 'Entra',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
    );
  }
}

/// Poster senza foto: palco scuro con Dot festaiolo che balla.
class _EventPoster extends StatelessWidget {
  const _EventPoster();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.darkSurfaceHigh,
      child: Center(child: PartyDot(size: 168)),
    );
  }
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({required this.label, required this.live});
  final String label;
  final bool live;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live ? AppColors.accent : AppColors.ink.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            FadeTransition(
              opacity: Tween(begin: .35, end: 1.0).animate(_c),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            widget.label,
            style: AppTextStyles.eyebrow(
              context,
            ).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Riga tratteggiata con due mezzelune ai lati, come un biglietto.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: CustomPaint(painter: _PerforationPainter()),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final bg = Paint()..color = AppColors.darkBackground;
    canvas.drawCircle(Offset(0, y), 10, bg);
    canvas.drawCircle(Offset(size.width, y), 10, bg);
    final dash = Paint()
      ..color = AppColors.paper.withValues(alpha: .18)
      ..strokeWidth = 1.5;
    for (var x = 18.0; x < size.width - 18; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(x + 5, y), dash);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => false;
}

/// Avviso sull'età: "18+" per le serate riservate ai maggiorenni e, per chi
/// ha meno di 18 anni, un promemoria sull'alcol.
class _AgeNotice extends StatelessWidget {
  const _AgeNotice({required this.adultsOnly, required this.minor});

  final bool adultsOnly;
  final bool minor;

  @override
  Widget build(BuildContext context) {
    final text = adultsOnly && minor
        ? 'Serata riservata ai maggiorenni: puoi vedere i ricordi della tua cerchia, ma non lasciare drop.'
        : adultsOnly
        ? 'Serata riservata ai maggiorenni.'
        : 'Alle serate possono servire alcolici: sotto i 18 anni non si possono comprare né bere. Divertiti in sicurezza.';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.accentSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.accentSecondary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              adultsOnly ? '18+' : '!',
              style: AppTextStyles.body(context).copyWith(
                color: AppColors.darkBackground,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                context,
              ).copyWith(fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
