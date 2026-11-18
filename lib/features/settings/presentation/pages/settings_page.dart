import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/presentation/pages/blocked_users_page.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/home_zone/home_zone.dart';
import 'package:echo/features/home_zone/home_zone_page.dart';
import 'package:echo/features/legal/legal_page.dart';
import 'package:echo/features/messaging/presentation/widgets/circle_nearby_row.dart';
import 'package:echo/features/messaging/providers/messaging_provider.dart'
    as messaging;
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Schermata Impostazioni: sezioni raggruppate in card "glass" come nelle
/// app social (account in cima, privacy, info legali, zona uscita in fondo).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.onEditProfile});

  /// Apre il foglio di modifica profilo (vive in ProfilePage).
  final VoidCallback onEditProfile;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  void _invalidateSession() {
    ref.invalidate(messaging.conversationsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(currentProfileProvider);
    ref.invalidate(myConnectionsProvider);
    ref.invalidate(pendingRequestsProvider);
  }

  Future<void> _logout() async {
    final ok = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Uscire da mingle?',
      message: 'Potrai rientrare quando vuoi con email e password.',
      confirmLabel: 'Esci',
      cancelLabel: 'Annulla',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(authRepositoryProvider).signOut();
    if (!mounted) return;
    _invalidateSession();
    // Il redirect del router porta al login e chiude anche questa pagina.
  }

  Future<void> _deleteAccount() async {
    final ok = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Elimina account',
      message:
          'Questa azione è permanente e irreversibile.\n\n'
          'Tutti i tuoi drop, messaggi e connessioni verranno eliminati definitivamente.',
      confirmLabel: 'Elimina definitivamente',
      cancelLabel: 'Annulla',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (!mounted) return;
      _invalidateSession();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      EchoToast.show(context, e.toString(), type: EchoToastType.error);
    }
  }

  Future<void> _changePassword(String email) async {
    final ok = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Cambia password',
      message: 'Ti mandiamo un link a $email per sceglierne una nuova.',
      confirmLabel: 'Invia link',
      cancelLabel: 'Annulla',
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      if (!mounted) return;
      EchoToast.show(
        context,
        'Link inviato, controlla la tua email',
        type: EchoToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      EchoToast.show(
        context,
        'Non sono riuscito a inviare il link. Riprova.',
        type: EchoToastType.error,
      );
    }
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(currentProfileProvider).asData?.value;
    final email = ref.watch(currentUserProvider)?.email ?? '';
    final sharing = ref.watch(shareDistanceProvider).asData?.value ?? false;
    final blockedCount = ref.watch(blockedUsersProvider).asData?.value.length;
    final homeZone = ref.watch(homeZoneProvider).asData?.value.zone;

    final sections = <Widget>[
      if (profile != null)
        _AccountCard(profile: profile, onTap: widget.onEditProfile),

      _Section(
        title: 'Account',
        children: [
          _Tile(
            icon: LucideIcons.userCog,
            title: 'Modifica profilo',
            subtitle: 'Nome, username, bio e foto',
            onTap: widget.onEditProfile,
          ),
          _Tile(icon: LucideIcons.mail, title: 'Email', subtitle: email),
          _Tile(
            icon: LucideIcons.keyRound,
            title: 'Cambia password',
            subtitle: 'Ricevi un link via email',
            onTap: email.isEmpty ? null : () => _changePassword(email),
          ),
        ],
      ),

      _Section(
        title: 'Privacy e sicurezza',
        children: [
          _Tile(
            icon: LucideIcons.home,
            title: 'Zona casa',
            subtitle: homeZone == null
                ? 'Non impostata: i drop da casa non sono protetti'
                : 'Attiva · raggio ${homeZone.radiusMeters.round()} m · solo su questo telefono',
            onTap: () => openHomeZonePage(context),
          ),
          _Tile(
            icon: LucideIcons.navigation,
            title: 'Mostra la mia distanza',
            subtitle: sharing
                ? 'La tua cerchia vede quanto sei lontano'
                : 'Nessuno vede quanto sei lontano',
            trailing: Switch.adaptive(
              value: sharing,
              activeTrackColor: AppColors.accent,
              onChanged: (v) => toggleShareDistance(context, ref, enable: v),
            ),
            onTap: () => toggleShareDistance(context, ref, enable: !sharing),
          ),
          _Tile(
            icon: LucideIcons.ban,
            title: 'Utenti bloccati',
            subtitle: switch (blockedCount) {
              null => 'Chi non può vederti né scriverti',
              0 => 'Nessuno al momento',
              1 => '1 persona',
              final n => '$n persone',
            },
            onTap: () => _push(const BlockedUsersPage()),
          ),
        ],
      ),

      _Section(
        title: 'Info e regole',
        children: [
          _Tile(
            icon: LucideIcons.heartHandshake,
            title: LegalDocument.guidelines.title,
            onTap: () => openLegal(context, LegalDocument.guidelines),
          ),
          _Tile(
            icon: LucideIcons.shieldCheck,
            title: LegalDocument.privacy.title,
            onTap: () => openLegal(context, LegalDocument.privacy),
          ),
          _Tile(
            icon: LucideIcons.fileText,
            title: LegalDocument.terms.title,
            onTap: () => openLegal(context, LegalDocument.terms),
          ),
        ],
      ),

      _Section(
        children: [
          _Tile(
            icon: LucideIcons.logOut,
            title: 'Esci',
            onTap: _busy ? null : _logout,
            showChevron: false,
          ),
          _Tile(
            icon: LucideIcons.trash2,
            title: 'Elimina account',
            titleColor: AppColors.error,
            onTap: _busy ? null : _deleteAccount,
            showChevron: false,
          ),
        ],
      ),

      const _Footer(),
    ];

    final content = SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingGlassHeaderDelegate(
              isDark: isDark,
              minExtent: 52,
              maxExtent: 72,
              padding: const EdgeInsets.fromLTRB(12, 16, 20, 8),
              pinnedGap: 0,
              pinned: (context) => Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Impostazioni',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_busy)
                    const MingleDotsLoader(size: 18, color: AppColors.accent),
                ],
              ),
              dissolving: (context) => const SizedBox.shrink(),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            sliver: SliverList.list(
              children: [
                for (var i = 0; i < sections.length; i++)
                  sections[i]
                      .animate(delay: (60 * i).ms)
                      .fadeIn(duration: 320.ms)
                      .slideY(
                        begin: 0.08,
                        curve: Curves.easeOutCubic,
                        duration: 380.ms,
                      ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: isDark
          ? AnimatedGradientBackground(child: content)
          : ColoredBox(color: AppColors.lightBackground, child: content),
    );
  }
}

// ─── Account card ────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.profile, required this.onTap});
  final ProfileModel profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: _Glass(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.darkSurfaceHigh,
                    backgroundImage: profile.avatarUrl != null
                        ? CachedNetworkImageProvider(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? Text(
                            name.characters.first.toUpperCase(),
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${profile.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text(
                    'Modifica',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sezioni ─────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = Divider(
      height: 1,
      thickness: 0.5,
      indent: 56,
      color: isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.06),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                title!.toUpperCase(),
                style: AppTextStyles.bodySecondary(context).copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          _Glass(
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) divider,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTextStyles.bodySecondary(context).color;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icone monocromatiche: il colore resta solo per le azioni
            // distruttive (titleColor).
            SizedBox(
              width: 28,
              child: Icon(
                icon,
                size: 21,
                color:
                    titleColor ??
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(context).copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        subtitle!,
                        key: ValueKey(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null && showChevron)
              Icon(
                Icons.chevron_right_rounded,
                color: secondary?.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Footer ──────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        children: [
          const MingleWordmark(
            fontSize: 20,
            color: AppColors.accent,
            dotColor: AppColors.accentSecondary,
          ),
          const SizedBox(height: 6),
          Text(
            'La mappa segreta della tua città.',
            style: AppTextStyles.bodySecondary(
              context,
            ).copyWith(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
