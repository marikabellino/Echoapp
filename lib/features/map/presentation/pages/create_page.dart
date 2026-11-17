import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/core/services/permission_gate.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/presentation/widgets/tag_people_sheet.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/events/domain/models/event_model.dart';
import 'package:echo/features/events/providers/events_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:echo/shared/widgets/navigation/floating_navbar.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key, this.initialEvent});

  final EventModel? initialEvent;

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  final _controller = TextEditingController();
  DropVisibility _visibility = DropVisibility.public;
  List<ProfileModel> _taggedUsers = [];
  bool _saving = false;
  String? _aiCaption;
  Uint8List? _imageBytes;
  EventModel? _selectedEvent;
  geo.Position? _gpsPosition;
  String? _gpsLabel;

  _LocationMode _locationMode = _LocationMode.gps;
  double? _searchedLat;
  double? _searchedLng;
  String? _searchedLabel;
  bool _locationAvailable = true;

  @override
  void initState() {
    super.initState();
    _selectedEvent = widget.initialEvent;
    if (_selectedEvent != null) _visibility = DropVisibility.public;
    _controller.addListener(_onTextChanged);
    _checkLocationAvailability();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _checkLocationAvailability() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    final perm = await geo.Geolocator.checkPermission();
    final available =
        serviceEnabled &&
        perm != geo.LocationPermission.denied &&
        perm != geo.LocationPermission.deniedForever;
    if (!mounted) return;
    setState(() {
      _locationAvailable = available;
      if (!available) _locationMode = _LocationMode.search;
    });
    if (available) {
      final pos = await _getLocation();
      if (!mounted || pos == null) return;
      setState(() => _gpsPosition = pos);
      final label = await _getLocationName(pos.latitude, pos.longitude);
      if (mounted) setState(() => _gpsLabel = label);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  ({double lat, double lng})? get _eventQueryCoords {
    final preset = ref.watch(mapCreateLocationProvider);
    if (preset != null) return preset;
    if (_locationMode == _LocationMode.search &&
        _searchedLat != null &&
        _searchedLng != null) {
      return (lat: _searchedLat!, lng: _searchedLng!);
    }
    if (_gpsPosition != null) {
      return (lat: _gpsPosition!.latitude, lng: _gpsPosition!.longitude);
    }
    return null;
  }

  bool get _ready => _imageBytes != null && _controller.text.trim().isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _imageBytes = bytes);
  }

  Future<void> _changeImage(BuildContext buttonContext) async {
    final source = await showAdaptiveActionSheet<ImageSource>(
      context: buttonContext,
      title: 'Cambia foto',
      actions: const [
        AdaptiveAction(
          value: ImageSource.camera,
          label: 'Fotocamera',
          icon: Icons.camera_alt_outlined,
        ),
        AdaptiveAction(
          value: ImageSource.gallery,
          label: 'Galleria',
          icon: Icons.photo_library_outlined,
        ),
      ],
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _drop() async {
    final text = _controller.text.trim();
    if (_imageBytes == null) {
      _showSnack('Parti da una foto.', type: EchoToastType.error);
      return;
    }
    if (text.isEmpty) {
      _showSnack('Aggiungi due parole al tuo drop.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(dropRepositoryProvider);
      final preset = ref.read(mapCreateLocationProvider);

      double lat, lng;
      String? locationName;
      if (_selectedEvent != null) {
        lat = _selectedEvent!.latitude;
        lng = _selectedEvent!.longitude;
        locationName = _selectedEvent!.venueName;
      } else if (preset != null) {
        lat = preset.lat;
        lng = preset.lng;
        locationName = await _getLocationName(lat, lng);
        ref.read(mapCreateLocationProvider.notifier).clear();
      } else if (_locationMode == _LocationMode.search &&
          _searchedLat != null &&
          _searchedLng != null) {
        lat = _searchedLat!;
        lng = _searchedLng!;
        locationName = _searchedLabel;
      } else {
        final position = await _getLocation();
        if (position == null) {
          setState(() => _saving = false);
          return;
        }
        lat = position.latitude;
        lng = position.longitude;
        locationName = await _getLocationName(
          position.latitude,
          position.longitude,
        );
      }

      final imageUrl = await repo.uploadDropImage(_imageBytes!);

      final newDrop = await repo.createDrop(
        description: text,
        mood: DropMood.drop,
        latitude: lat,
        longitude: lng,
        locationName: locationName,
        imageUrl: imageUrl,
        aiCaption: _aiCaption,
        visibility: _visibility,
        eventId: _selectedEvent?.id,
      );

      String? skippedTagsWarning;
      if (_taggedUsers.isNotEmpty) {
        try {
          final taggedIds = await repo.tagUsersOnDrop(
            newDrop.id,
            _taggedUsers.map((u) => u.id).toList(),
          );
          final skipped = _taggedUsers
              .where((u) => !taggedIds.contains(u.id))
              .toList();
          if (skipped.isNotEmpty) {
            final names = skipped
                .map(
                  (u) => u.displayName.isNotEmpty ? u.displayName : u.username,
                )
                .join(', ');
            skippedTagsWarning =
                'Non taggat* (non siete nella stessa cerchia): $names.';
          }
        } catch (_) {
          skippedTagsWarning =
              'Non è stato possibile taggare le persone selezionate.';
        }
      }

      final userId = ref.read(currentUserProvider)?.id;
      ref.invalidate(discoverProvider);
      if (userId != null) ref.invalidate(userDropsProvider(userId));
      ref.invalidate(currentProfileProvider);

      if (mounted) {
        HapticFeedback.mediumImpact();
        _controller.clear();
        setState(() {
          _visibility = DropVisibility.public;
          _taggedUsers = [];
          _aiCaption = null;
          _imageBytes = null;
          _selectedEvent = null;
          _locationMode = _locationAvailable
              ? _LocationMode.gps
              : _LocationMode.search;
          _searchedLat = null;
          _searchedLng = null;
          _searchedLabel = null;
        });
        _showSnack(
          skippedTagsWarning != null
              ? 'Drop lasciato nel mondo. $skippedTagsWarning'
              : 'Drop lasciato nel mondo.',
          type: skippedTagsWarning != null
              ? EchoToastType.info
              : EchoToastType.success,
        );
        ref.read(mapFlyTargetProvider.notifier).set(newDrop);
        if (widget.initialEvent != null) {
          Navigator.of(context).pop();
        } else {
          ref.read(shellIndexProvider.notifier).setIndex(1);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Non è stato possibile lasciare il drop. Riprova.',
          type: EchoToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<geo.Position?> _getLocation() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack(
          'Attiva la posizione dalle impostazioni del telefono.',
          type: EchoToastType.error,
        );
        return null;
      }
      final perm = await PermissionGate.run(
        () => geo.Geolocator.requestPermission(),
      );
      if (perm == geo.LocationPermission.deniedForever) {
        _showSnack(
          'Permesso posizione negato. Attivalo dalle impostazioni o scegli un luogo.',
          type: EchoToastType.error,
        );
        return null;
      }
      if (perm == geo.LocationPermission.denied) {
        _showSnack(
          'Serve il permesso di posizione, oppure scegli un luogo.',
          type: EchoToastType.error,
        );
        return null;
      }
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      _showSnack(
        'Non riesco a rilevare la posizione. Riprova o cerca un luogo.',
        type: EchoToastType.error,
      );
      return null;
    }
  }

  Future<String?> _getLocationName(double lat, double lng) async {
    try {
      final marks = await gc.placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final m = marks.first;
        final parts = [
          (m.street?.isNotEmpty ?? false) ? m.street : m.name,
          m.locality,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    return null;
  }

  void _showSnack(String msg, {EchoToastType type = EchoToastType.info}) {
    if (!mounted) return;
    EchoToast.show(context, msg, type: type);
  }

  Future<void> _openLocationSheet() async {
    if (_selectedEvent != null) {
      _showSnack('Il drop è agganciato al luogo dell\'evento.');
      return;
    }
    FocusScope.of(context).unfocus();
    final pick = await showModalBottomSheet<_LocationPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) =>
          _LocationSheet(gpsAvailable: _locationAvailable, gpsLabel: _gpsLabel),
    );
    if (pick == null || !mounted) return;
    ref.read(mapCreateLocationProvider.notifier).clear();
    setState(() {
      if (pick.place == null) {
        _locationMode = _LocationMode.gps;
        _searchedLat = null;
        _searchedLng = null;
        _searchedLabel = null;
      } else {
        _locationMode = _LocationMode.search;
        _searchedLat = pick.place!.lat;
        _searchedLng = pick.place!.lng;
        _searchedLabel = pick.place!.shortLabel;
      }
    });
    if (pick.place == null && _gpsPosition == null) {
      final pos = await _getLocation();
      if (!mounted || pos == null) return;
      setState(() => _gpsPosition = pos);
      final label = await _getLocationName(pos.latitude, pos.longitude);
      if (mounted) setState(() => _gpsLabel = label);
    }
  }

  Future<void> _openTagPicker() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<List<ProfileModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TagPeopleSheet(initiallySelected: _taggedUsers),
    );
    if (result != null && mounted) setState(() => _taggedUsers = result);
  }

  Future<void> _openEventPicker(
    BuildContext buttonContext,
    List<EventModel> events,
  ) async {
    final picked = await showAdaptiveActionSheet<String>(
      context: buttonContext,
      title: 'Fai parte di un evento?',
      actions: [
        for (final e in events)
          AdaptiveAction(
            value: e.id,
            label: '${e.title} · ${e.venueName}',
            icon: Icons.event_rounded,
          ),
        const AdaptiveAction(
          value: '',
          label: 'Nessun evento',
          icon: Icons.close_rounded,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedEvent = picked.isEmpty
          ? null
          : events.firstWhere((e) => e.id == picked);
      if (_selectedEvent != null) _visibility = DropVisibility.public;
    });
  }

  ({String label, IconData icon, bool locked}) _locationInfo(
    ({double lat, double lng})? preset,
  ) {
    if (_selectedEvent != null) {
      return (
        label: _selectedEvent!.venueName,
        icon: Icons.lock_outline_rounded,
        locked: true,
      );
    }
    if (preset != null) {
      return (
        label: 'Punto scelto sulla mappa',
        icon: Icons.push_pin_rounded,
        locked: false,
      );
    }
    if (_locationMode == _LocationMode.search) {
      return (
        label: _searchedLabel ?? 'Scegli dove lasciarlo',
        icon: Icons.place_rounded,
        locked: false,
      );
    }
    return (
      label: _gpsLabel ?? 'Qui, dove sei adesso',
      icon: Icons.near_me_rounded,
      locked: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    final preset = ref.watch(mapCreateLocationProvider);
    final top = MediaQuery.paddingOf(context).top;
    final pushed = widget.initialEvent != null;
    final ctaBottom = pushed
        ? MediaQuery.paddingOf(context).bottom + 16
        : FloatingNavbar.reservedHeight + 4;
    final location = _locationInfo(preset);
    final keyboardOpen =
        MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1.1),
                  radius: 1.3,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.22),
                    AppColors.darkBackground.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          if (!isOnline)
            const OfflinePlaceholder(
              message: 'Torna online per aggiungere un drop.',
            )
          else ...[
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  top + 12,
                  16,
                  ctaBottom + 96 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, pushed),
                    const SizedBox(height: 14),
                    _LocationPill(
                      label: location.label,
                      icon: location.icon,
                      locked: location.locked,
                      color: AppColors.accent,
                      onTap: _openLocationSheet,
                    ),
                    const SizedBox(height: 16),
                    _composer(context),
                    const SizedBox(height: 26),
                    _options(context),
                  ],
                ),
              ),
            ),
            if (!keyboardOpen) ...[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: ctaBottom + 110,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.darkBackground,
                          AppColors.darkBackground,
                          AppColors.darkBackground.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: ctaBottom,
                child: _DropButton(
                  ready: _ready,
                  saving: _saving,
                  color: AppColors.accent,
                  onTap: _saving ? null : _drop,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool pushed) {
    return Row(
      children: [
        if (pushed) ...[
          GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            size: 42,
            iconSize: 20,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            'Nuovo drop',
            style: AppTextStyles.displayLarge(context).copyWith(fontSize: 32),
          ),
        ),
      ],
    );
  }

  Widget _composer(BuildContext context) {
    final hasImage = _imageBytes != null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            child: hasImage
                ? _photoPreview(context)
                : _EmptyPhoto(
                    color: AppColors.accent,
                    onCamera: () => _pickImage(ImageSource.camera),
                    onGallery: () => _pickImage(ImageSource.gallery),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 2,
              maxLength: 500,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => currentLength > 400
                  ? Text(
                      '$currentLength/$maxLength',
                      style: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(fontSize: 11),
                    )
                  : null,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.body(
                context,
              ).copyWith(fontSize: 16, height: 1.4),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Cosa sta succedendo qui?',
                hintStyle: AppTextStyles.bodySecondary(
                  context,
                ).copyWith(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPreview(BuildContext context) {
    return AspectRatio(
      key: const ValueKey('photo'),
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_imageBytes!, fit: BoxFit.cover, gaplessPlayback: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x8C000000),
                ],
                stops: [0, 0.25, 0.6, 1],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _RoundIcon(
              icon: Icons.close_rounded,
              onTap: () => setState(() => _imageBytes = null),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 14,
            child: Builder(
              builder: (buttonContext) => _GlassPill(
                icon: Icons.autorenew_rounded,
                label: 'Cambia',
                onTap: () => _changeImage(buttonContext),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options(BuildContext context) {
    final coords = _eventQueryCoords;
    final events = widget.initialEvent != null || coords == null
        ? const <EventModel>[]
        : ref.watch(nearbyActiveEventsProvider(coords)).asData?.value ??
              const <EventModel>[];

    if (_selectedEvent != null &&
        widget.initialEvent == null &&
        events.isNotEmpty &&
        !events.any((e) => e.id == _selectedEvent!.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedEvent = null);
      });
    }

    final locked = _selectedEvent != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chi lo vede',
                  style: AppTextStyles.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 12),
                _VisibilitySelector(
                  value: locked ? DropVisibility.public : _visibility,
                  enabled: !locked,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _visibility = v);
                  },
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _visibilityHintIcon(locked),
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _visibilityHint(locked),
                            style: AppTextStyles.bodySecondary(
                              context,
                            ).copyWith(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _RowDivider(),
          _OptionRow(
            icon: Icons.alternate_email_rounded,
            title: 'Tagga amici',
            trailing: _taggedUsers.isEmpty
                ? _trailingText('Nessuno')
                : _AvatarStack(users: _taggedUsers),
            onTap: _openTagPicker,
          ),
          if (events.isNotEmpty || widget.initialEvent != null) ...[
            const _RowDivider(),
            Builder(
              builder: (buttonContext) => _OptionRow(
                icon: Icons.celebration_rounded,
                title: 'Evento',
                trailing: _trailingText(_selectedEvent?.title ?? 'Nessuno'),
                onTap: widget.initialEvent != null
                    ? null
                    : () => _openEventPicker(buttonContext, events),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _visibilityHintIcon(bool locked) {
    if (locked) return Icons.celebration_rounded;
    switch (_visibility) {
      case DropVisibility.public:
        return Icons.shield_outlined;
      case DropVisibility.circle:
        return Icons.group_outlined;
      case DropVisibility.private:
        return Icons.lock_outline_rounded;
    }
  }

  String _visibilityHint(bool locked) {
    if (locked) {
      return 'Durante l\'evento il drop è visibile a tutti. Quando finisce resta solo a te e alla tua cerchia.';
    }
    switch (_visibility) {
      case DropVisibility.public:
        return 'Tutti lo vedranno nel punto in cui lo lasci. A casa tua o nei posti di tutti i giorni meglio Cerchia o Solo io.';
      case DropVisibility.circle:
        return 'Solo le persone nella tua cerchia potranno trovarlo.';
      case DropVisibility.private:
        return 'Resta solo sulla tua mappa, come un diario.';
    }
  }

  Widget _trailingText(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 14),
      ),
    );
  }
}

class _EmptyPhoto extends StatelessWidget {
  const _EmptyPhoto({
    required this.color,
    required this.onCamera,
    required this.onGallery,
  });

  final Color color;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: const ValueKey('empty'),
      duration: const Duration(milliseconds: 400),
      height: 300,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(Icons.photo_camera_rounded, size: 28, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            'Parti da una foto',
            style: AppTextStyles.body(
              context,
            ).copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Cattura il momento, poi aggiungi due parole.',
            style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SourceButton(
                icon: Icons.camera_alt_rounded,
                label: 'Scatta',
                filled: true,
                color: color,
                onTap: onCamera,
              ),
              const SizedBox(width: 10),
              _SourceButton(
                icon: Icons.photo_library_rounded,
                label: 'Galleria',
                filled: false,
                color: color,
                onTap: onGallery,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceButton extends StatefulWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SourceButton> createState() => _SourceButtonState();
}

class _SourceButtonState extends State<_SourceButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.filled ? AppColors.darkBackground : Colors.white;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: widget.filled
                ? widget.color
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: widget.filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilitySelector extends StatelessWidget {
  const _VisibilitySelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final DropVisibility value;
  final bool enabled;
  final ValueChanged<DropVisibility> onChanged;

  static String _label(DropVisibility v) => switch (v) {
    DropVisibility.public => 'Tutti',
    DropVisibility.circle => 'Cerchia',
    DropVisibility.private => 'Solo io',
  };

  @override
  Widget build(BuildContext context) {
    const values = DropVisibility.values;
    final index = values.indexOf(value);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment(index - 1.0, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / values.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(v),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                v.icon,
                                size: 15,
                                color: v == value
                                    ? AppColors.darkBackground
                                    : Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _label(v),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: v == value
                                      ? AppColors.darkBackground
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _LocationPill extends StatelessWidget {
  const _LocationPill({
    required this.label,
    required this.icon,
    required this.locked,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool locked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(
                  context,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (!locked) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.75)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            trailing,
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.users});
  final List<ProfileModel> users;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(3).toList();
    final extra = users.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26.0 + (shown.length - 1) * 18,
          height: 26,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 18.0,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.darkSurface,
                    ),
                    child: _MiniAvatar(user: shown[i]),
                  ),
                ),
            ],
          ),
        ),
        if (extra > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$extra',
            style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.user});
  final ProfileModel user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty ? user.displayName : user.username;
    return CircleAvatar(
      radius: 11.5,
      backgroundColor: AppColors.darkSurfaceHigh,
      backgroundImage: user.avatarUrl != null
          ? CachedNetworkImageProvider(user.avatarUrl!)
          : null,
      child: user.avatarUrl == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropButton extends StatefulWidget {
  const _DropButton({
    required this.ready,
    required this.saving,
    required this.color,
    required this.onTap,
  });

  final bool ready;
  final bool saving;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_DropButton> createState() => _DropButtonState();
}

class _DropButtonState extends State<_DropButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.ready || widget.saving;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active ? null : AppColors.darkSurfaceHigh,
            gradient: active
                ? LinearGradient(
                    colors: [
                      widget.color,
                      Color.lerp(widget.color, Colors.white, 0.3)!,
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: widget.saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.darkBackground,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 20,
                      color: active
                          ? AppColors.darkBackground
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Lascia il drop',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: active
                            ? AppColors.darkBackground
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LocationPick {
  const _LocationPick.gps() : place = null;
  const _LocationPick.place(this.place);
  final _LocationSuggestion? place;
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.gpsAvailable, required this.gpsLabel});

  final bool gpsAvailable;
  final String? gpsLabel;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<_LocationSuggestion> _suggestions = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _fetch(value.trim()),
    );
  }

  Future<void> _fetch(String query) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(query)}.json'
        '?key=${AppConstants.maptilerKey}'
        '&types=address,poi,place'
        '&limit=4'
        '&language=it',
      );
      final res = await http.get(uri);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>;
        setState(
          () => _suggestions = features.map((f) {
            final coords = f['geometry']['coordinates'] as List<dynamic>;
            return _LocationSuggestion(
              (coords[1] as num).toDouble(),
              (coords[0] as num).toDouble(),
              f['place_name'] as String,
            );
          }).toList(),
        );
      } else {
        setState(() => _suggestions = []);
      }
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_suggestions.isNotEmpty) {
      Navigator.of(context).pop(_LocationPick.place(_suggestions.first));
      return;
    }
    final query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final locations = await gc.locationFromAddress(query);
      if (!mounted) return;
      if (locations.isNotEmpty) {
        final loc = locations.first;
        Navigator.of(context).pop(
          _LocationPick.place(
            _LocationSuggestion(loc.latitude, loc.longitude, query),
          ),
        );
        return;
      }
      EchoToast.show(context, 'Luogo non trovato', type: EchoToastType.error);
    } catch (_) {
      if (mounted) {
        EchoToast.show(context, 'Luogo non trovato', type: EchoToastType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    final maxHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        insets -
        24;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            (insets > 0 ? 0 : safe) + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Dove lo lasci?',
                  style: AppTextStyles.headline(
                    context,
                  ).copyWith(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.gpsAvailable) ...[
                _SheetTile(
                  icon: Icons.near_me_rounded,
                  color: AppColors.accent,
                  title: 'Qui, dove sei adesso',
                  subtitle: widget.gpsLabel,
                  onTap: () =>
                      Navigator.of(context).pop(const _LocationPick.gps()),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        autofocus: !widget.gpsAvailable,
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        onSubmitted: (_) => _submit(),
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(fontSize: 15),
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          hintText: 'Cerca un posto o un indirizzo',
                          hintStyle: AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(fontSize: 15),
                        ),
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Column(
                  children: [
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _SheetTile(
                          icon: Icons.place_rounded,
                          color: Colors.white,
                          title: s.label.split(',').first,
                          subtitle: s.label.contains(',')
                              ? s.label
                                    .substring(s.label.indexOf(',') + 1)
                                    .trim()
                              : null,
                          onTap: () =>
                              Navigator.of(context).pop(_LocationPick.place(s)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Il drop viene lasciato in quel punto preciso. Se è pubblico, evita casa tua.',
                      style: AppTextStyles.bodySecondary(
                        context,
                      ).copyWith(fontSize: 12, height: 1.4),
                    ),
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

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12.5),
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

enum _LocationMode { gps, search }

class _LocationSuggestion {
  final double lat, lng;
  final String label;
  const _LocationSuggestion(this.lat, this.lng, this.label);

  String get shortLabel {
    final parts = label.split(',').map((p) => p.trim()).toList();
    if (parts.length < 3) return parts.first;
    final city = parts[parts.length - 2].replaceFirst(RegExp(r'^\d+\s*'), '');
    if (city.isEmpty || city == parts.first) return parts.first;
    return '${parts.first}, $city';
  }
}
