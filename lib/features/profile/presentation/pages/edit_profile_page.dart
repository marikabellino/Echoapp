import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/presentation/widgets/auth_field_feedback.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/brand/mingle_animations.dart';
import 'package:echo/shared/widgets/collapsing_glass_header.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

/// Modifica profilo a schermo intero, stile app social: foto in alto,
/// campi sotto, "Salva" nell'header attivo solo se qualcosa è cambiato.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key, required this.profile});
  final ProfileModel profile;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final _nameCtrl = TextEditingController(
    text: widget.profile.displayName,
  );
  late final _usernameCtrl = TextEditingController(
    text: widget.profile.username,
  );
  late final _bioCtrl = TextEditingController(text: widget.profile.bio);

  bool _saving = false;
  bool _uploading = false;

  Timer? _usernameDebounce;
  int _usernameSeq = 0;
  UsernameStatus _usernameStatus = UsernameStatus.idle;
  String? _usernameError;

  static const _cooldown = Duration(days: 30);
  static const _bioMax = 150;
  static final _usernameChars = RegExp(r'^[a-zA-Z0-9_]+$');

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _usernameCtrl, _bioCtrl]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ─── Stato ────────────────────────────────────────────────────────────────

  String get _newUsername => _usernameCtrl.text.trim().toLowerCase();
  bool get _usernameChanged => _newUsername != widget.profile.username;

  bool get _dirty =>
      _nameCtrl.text.trim() != widget.profile.displayName ||
      _bioCtrl.text.trim() != widget.profile.bio ||
      _usernameChanged;

  bool get _canSave =>
      _dirty &&
      !_saving &&
      _usernameStatus != UsernameStatus.taken &&
      _usernameStatus != UsernameStatus.invalid;

  /// null = può cambiare username subito.
  Duration? get _cooldownRemaining {
    final changedAt = widget.profile.usernameChangedAt;
    if (changedAt == null) return null;
    final remaining = _cooldown - DateTime.now().difference(changedAt);
    return remaining.isNegative ? null : remaining;
  }

  // ─── Username live ────────────────────────────────────────────────────────

  void _onUsernameChanged(String raw) {
    _usernameDebounce?.cancel();
    _usernameSeq++;
    final v = raw.trim();
    UsernameStatus next;
    if (v.isEmpty || v.toLowerCase() == widget.profile.username) {
      next = UsernameStatus.idle;
    } else if (!_usernameChars.hasMatch(v)) {
      next = UsernameStatus.invalid;
    } else if (v.length < 3) {
      next = UsernameStatus.idle;
    } else {
      next = UsernameStatus.checking;
      _usernameDebounce = Timer(
        const Duration(milliseconds: 450),
        _checkUsername,
      );
    }
    setState(() {
      _usernameStatus = next;
      _usernameError = null;
    });
  }

  Future<void> _checkUsername() async {
    final seq = ++_usernameSeq;
    UsernameStatus result;
    try {
      final free = await ref
          .read(authRepositoryProvider)
          .isUsernameAvailable(_newUsername);
      result = free ? UsernameStatus.available : UsernameStatus.taken;
    } catch (_) {
      result = UsernameStatus.error;
    }
    if (mounted && seq == _usernameSeq) {
      setState(() => _usernameStatus = result);
    }
  }

  // ─── Salvataggio ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_usernameChanged) {
      final v = _newUsername;
      final error = v.isEmpty
          ? 'Scegli un username'
          : v.length < 3
          ? 'Minimo 3 caratteri'
          : !_usernameChars.hasMatch(v)
          ? 'Solo lettere, numeri e _'
          : null;
      if (error != null) {
        setState(() => _usernameError = error);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(currentProfileProvider.notifier)
          .saveProfile(
            displayName: _nameCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            username: _usernameChanged ? _newUsername : null,
          );
      if (!mounted) return;
      EchoToast.show(
        context,
        'Profilo aggiornato',
        type: EchoToastType.success,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final message =
          s.contains('duplicate key') || s.contains('profiles_username_key')
          ? 'Username già in uso.'
          : s.contains('cambiare username')
          ? 'Puoi cambiare username una volta ogni 30 giorni.'
          : 'Non sono riuscito a salvare. Riprova.';
      EchoToast.show(context, message, type: EchoToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _maybeLeave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Scartare le modifiche?',
      message: 'Se esci adesso, le modifiche non salvate andranno perse.',
      confirmLabel: 'Scarta',
      cancelLabel: 'Continua a modificare',
      destructive: true,
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ─── Foto profilo ─────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final ImageSource? source;
    if (Platform.isIOS || Platform.isMacOS) {
      source = await showCupertinoModalPopup<ImageSource>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
              child: const Text('Scatta una foto'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
              child: const Text('Scegli dalla libreria'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
        ),
      );
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black54,
        builder: (ctx) => EchoBottomSheet(
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Scatta una foto'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Scegli dalla galleria'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }
    if (source == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 400,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final notifier = ref.read(currentProfileProvider.notifier);
      final url = await notifier.uploadAvatar(bytes);
      // Salva solo la foto: nome/bio restano quelli già salvati, le modifiche
      // in corso nei campi non vengono toccate.
      final saved = ref.read(currentProfileProvider).asData?.value;
      await notifier.saveProfile(
        displayName: saved?.displayName ?? widget.profile.displayName,
        bio: saved?.bio ?? widget.profile.bio,
        avatarUrl: url,
      );
    } catch (_) {
      if (mounted) {
        EchoToast.show(
          context,
          'Non sono riuscito a caricare la foto. Riprova.',
          type: EchoToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final live = ref.watch(currentProfileProvider).asData?.value;
    final avatarUrl = live?.avatarUrl ?? widget.profile.avatarUrl;
    final remaining = _cooldownRemaining;
    final locked = remaining != null;

    final content = SafeArea(
      bottom: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              pinnedGap: 0,
              pinned: (context) => Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: _maybeLeave,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modifica profilo',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _SaveButton(
                    enabled: _canSave,
                    saving: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
              dissolving: (context) => const SizedBox.shrink(),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.paddingOf(context).bottom +
                  MediaQuery.viewInsetsOf(context).bottom +
                  32,
            ),
            sliver: SliverList.list(
              children:
                  [
                        // ── Foto ──
                        Center(
                          child: _AvatarPicker(
                            url: avatarUrl,
                            initial: _initial,
                            uploading: _uploading,
                            onTap: _uploading ? null : _pickAvatar,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: _uploading ? null : _pickAvatar,
                            child: Text(
                              avatarUrl == null
                                  ? 'Aggiungi foto'
                                  : 'Cambia foto',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ── Nome ──
                        const _Label('Nome'),
                        _input(
                          controller: _nameCtrl,
                          hint: 'Come vuoi farti chiamare',
                          capitalization: TextCapitalization.words,
                          maxLength: 40,
                        ),
                        const SizedBox(height: 20),

                        // ── Username ──
                        const _Label('Username'),
                        _input(
                          controller: _usernameCtrl,
                          hint: 'username',
                          prefix: '@',
                          enabled: !locked,
                          onChanged: _onUsernameChanged,
                          errorText: _usernameError,
                          suffix: UsernameStatusIcon(status: _usernameStatus),
                        ),
                        UsernameStatusLine(
                          status: _usernameStatus,
                          username: _newUsername,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Text(
                            locked
                                ? 'Potrai cambiarlo di nuovo tra ${remaining.inDays + 1} giorni.'
                                : 'Puoi cambiarlo una volta ogni 30 giorni.',
                            style: AppTextStyles.bodySecondary(
                              context,
                            ).copyWith(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Bio ──
                        Row(
                          children: [
                            const Expanded(child: _Label('Bio')),
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 8,
                                bottom: 8,
                              ),
                              child: Text(
                                '${_bioCtrl.text.characters.length}/$_bioMax',
                                style: AppTextStyles.bodySecondary(context)
                                    .copyWith(
                                      fontSize: 12,
                                      color:
                                          _bioCtrl.text.characters.length >=
                                              _bioMax
                                          ? AppColors.accent
                                          : null,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        _input(
                          controller: _bioCtrl,
                          hint: 'Racconta qualcosa di te',
                          maxLines: 4,
                          maxLength: _bioMax,
                          radius: AppRadius.lg,
                        ),
                      ]
                      .animate(interval: 40.ms)
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: 0.06, curve: Curves.easeOutCubic),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: Scaffold(
        body: isDark
            ? AnimatedGradientBackground(child: content)
            : ColoredBox(color: AppColors.lightBackground, child: content),
      ),
    );
  }

  String get _initial {
    final p = widget.profile;
    final name = p.displayName.isNotEmpty ? p.displayName : p.username;
    return (name.characters.firstOrNull ?? '?').toUpperCase();
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    String? prefix,
    Widget? suffix,
    bool enabled = true,
    int maxLines = 1,
    int? maxLength,
    double radius = AppRadius.pill,
    String? errorText,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: c, width: w),
    );
    final idle = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.10);

    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      textCapitalization: capitalization,
      onChanged: onChanged,
      style: AppTextStyles.body(context).copyWith(fontSize: 15.5),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        suffixIcon: suffix,
        errorText: errorText,
        counterText: '',
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: enabled ? 0.07 : 0.03)
            : Colors.white.withValues(alpha: enabled ? 0.8 : 0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: border(idle),
        enabledBorder: border(idle),
        disabledBorder: border(idle.withValues(alpha: 0.05)),
        focusedBorder: border(AppColors.accent, 1.5),
        errorBorder: border(AppColors.accent),
        focusedErrorBorder: border(AppColors.accent, 1.5),
      ),
    );
  }
}

// ─── Pezzi ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.bodySecondary(context).copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });
  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || saving ? 1 : 0.4,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: enabled
              ? AppColors.accent
              : AppColors.accent.withValues(alpha: 0.25),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 36),
          shape: const StadiumBorder(),
        ),
        child: saving
            ? const MingleDotsLoader(size: 16, color: Colors.white)
            : const Text(
                'Salva',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.url,
    required this.initial,
    required this.uploading,
    required this.onTap,
  });
  final String? url;
  final String initial;
  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.darkSurfaceHigh,
              backgroundImage: url != null
                  ? CachedNetworkImageProvider(url!)
                  : null,
              child: uploading
                  ? const MingleLoader(size: 34)
                  : url == null
                  ? Text(
                      initial,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
          ),
          if (!uploading)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2.5,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
