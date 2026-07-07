import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/core/services/connectivity_service.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/offline_placeholder.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/events/domain/models/event_model.dart';
import 'package:echo/features/events/providers/events_provider.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/adaptive_dialog.dart';
import 'package:echo/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/gradient_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  final _controller = TextEditingController();
  final _locationSearchController = TextEditingController();
  DropMood _mood = DropMood.drop;
  DropVisibility _visibility = DropVisibility.public;
  List<ProfileModel> _taggedUsers = [];
  bool _saving = false;
  // bool _generatingAi = false; // TODO: AI v2
  String? _aiCaption;
  List<int>? _imageBytes;
  EventModel? _selectedEvent;
  geo.Position? _gpsPosition;

  _LocationMode _locationMode = _LocationMode.gps;
  double? _searchedLat;
  double? _searchedLng;
  String? _searchedLabel;
  bool _searchingLocation = false;
  List<_LocationSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Risolto una volta sola, solo per capire quali eventi vicini proporre —
    // la posizione effettiva del drop viene ricalcolata al submit.
    _getLocation().then((pos) {
      if (mounted && pos != null) setState(() => _gpsPosition = pos);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _locationSearchController.dispose();
    super.dispose();
  }

  // Posizione da usare per proporre gli eventi vicini: rispecchia la stessa
  // priorità usata al submit per il luogo effettivo del drop.
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

  // TODO: AI v2 — _generateCaption e _suggestMood rimossi dalla UI

  // ─── Image picker ────────────────────────────────────────────────────────────

  Future<void> _pickImage(BuildContext buttonContext) async {
    final source = await _showImageSourceSheet(buttonContext);
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  Future<ImageSource?> _showImageSourceSheet(BuildContext buttonContext) {
    return showAdaptiveActionSheet<ImageSource>(
      context: buttonContext,
      title: 'Aggiungi foto',
      actions: [
        const AdaptiveAction(
          value: ImageSource.camera,
          label: 'Fotocamera',
          icon: Icons.camera_alt_outlined,
        ),
        const AdaptiveAction(
          value: ImageSource.gallery,
          label: 'Galleria',
          icon: Icons.photo_library_outlined,
        ),
      ],
    );
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _drop() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnack('Scrivi qualcosa prima di lasciare un drop!');
      return;
    }
    if (_imageBytes == null) {
      _showSnack('Aggiungi una foto al drop.', type: EchoToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(dropRepositoryProvider);
      final preset = ref.read(mapCreateLocationProvider);

      double lat, lng;
      String? locationName;
      if (_selectedEvent != null) {
        // Con un evento selezionato il drop è agganciato al suo luogo,
        // niente GPS/ricerca manuale.
        lat = _selectedEvent!.latitude;
        lng = _selectedEvent!.longitude;
        locationName = _selectedEvent!.venueName;
      } else if (preset != null) {
        lat = preset.lat;
        lng = preset.lng;
        locationName = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        ref.read(mapCreateLocationProvider.notifier).clear();
      } else if (_locationMode == _LocationMode.search &&
          _searchedLat != null &&
          _searchedLng != null) {
        lat = _searchedLat!;
        lng = _searchedLng!;
        locationName = _searchedLabel;
      } else {
        final position = await _getLocation();
        lat = position?.latitude ?? 41.9028;
        lng = position?.longitude ?? 12.4964;
        locationName = await _getLocationName(position);
      }

      String? imageUrl;
      if (_imageBytes != null) {
        imageUrl = await repo.uploadDropImage(_imageBytes!.toUint8List());
      }

      final newDrop = await repo.createDrop(
        description: text,
        mood: _mood,
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
        final taggedIds = await repo.tagUsersOnDrop(
          newDrop.id,
          _taggedUsers.map((u) => u.id).toList(),
        );
        final skipped = _taggedUsers
            .where((u) => !taggedIds.contains(u.id))
            .toList();
        if (skipped.isNotEmpty) {
          final names = skipped
              .map((u) => u.displayName.isNotEmpty ? u.displayName : u.username)
              .join(', ');
          skippedTagsWarning =
              'Non taggat* (non siete nella stessa cerchia): $names.';
        }
      }

      final userId = ref.read(currentUserProvider)?.id;
      ref.invalidate(discoverProvider);
      if (userId != null) ref.invalidate(userDropsProvider(userId));
      ref.invalidate(currentProfileProvider);

      if (mounted) {
        _controller.clear();
        setState(() {
          _mood = DropMood.drop;
          _visibility = DropVisibility.public;
          _taggedUsers = [];
          _aiCaption = null;
          _imageBytes = null;
          _selectedEvent = null;
          _locationMode = _LocationMode.gps;
          _searchedLat = null;
          _searchedLng = null;
          _searchedLabel = null;
          _suggestions = [];
          _locationSearchController.clear();
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
        ref.read(shellIndexProvider.notifier).setIndex(1);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Errore: $e', type: EchoToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<geo.Position?> _getLocation() async {
    try {
      final perm = await geo.Geolocator.requestPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        return null;
      }
      return geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getLocationName(geo.Position? pos) async {
    if (pos == null) return null;
    try {
      final marks = await gc.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (marks.isNotEmpty) {
        final m = marks.first;
        return [
          m.street,
          m.locality,
          m.country,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
      }
    } catch (_) {}
    return '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _fetchSuggestions(value.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _searchingLocation = true);
    try {
      final encoded = Uri.encodeComponent(query);
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/$encoded.json'
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
        final results = features.map((f) {
          final coords = (f['geometry']['coordinates'] as List<dynamic>);
          return _LocationSuggestion(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
            f['place_name'] as String,
          );
        }).toList();
        setState(() => _suggestions = results);
      } else {
        setState(() => _suggestions = []);
      }
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searchingLocation = false);
    }
  }

  void _pickSuggestion(_LocationSuggestion s) {
    setState(() {
      _searchedLat = s.lat;
      _searchedLng = s.lng;
      _searchedLabel = s.label;
      _suggestions = [];
      _locationSearchController.text = s.label;
    });
  }

  Future<void> _searchLocation() async {
    final query = _locationSearchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searchingLocation = true);
    try {
      final locations = await gc.locationFromAddress(query);
      if (locations.isNotEmpty && mounted) {
        final loc = locations.first;
        String label = query;
        try {
          final marks = await gc.placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          );
          if (marks.isNotEmpty) {
            final m = marks.first;
            label = [
              m.street,
              m.locality,
              m.country,
            ].where((s) => s != null && s.isNotEmpty).join(', ');
            if (label.isEmpty) label = query;
          }
        } catch (_) {}
        setState(() {
          _searchedLat = loc.latitude;
          _searchedLng = loc.longitude;
          _searchedLabel = label;
        });
      } else if (mounted) {
        _showSnack('Indirizzo non trovato', type: EchoToastType.error);
      }
    } catch (_) {
      if (mounted)
        _showSnack('Indirizzo non trovato', type: EchoToastType.error);
    } finally {
      if (mounted) setState(() => _searchingLocation = false);
    }
  }

  void _showSnack(String msg, {EchoToastType type = EchoToastType.info}) {
    if (!mounted) return;
    EchoToast.show(context, msg, type: type);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider);
    final presetLocation = ref.watch(mapCreateLocationProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (isDark)
            const AnimatedGradientBackground(child: SizedBox.expand())
          else
            Container(
              decoration: const BoxDecoration(color: AppColors.lightBackground),
            ),
          if (!isOnline)
            const OfflinePlaceholder(
              message: 'Torna online per aggiungere un drop.',
            )
          else
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lascia un drop',
                      style: AppTextStyles.displayLarge(context),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sarà scoperto da chi passerà qui.',
                      style: AppTextStyles.bodySecondary(context),
                    ),
                    if (presetLocation != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accent.withValues(alpha: 0.16),
                              AppColors.accentSecondary.withValues(alpha: 0.16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 16,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Posizione dalla mappa: '
                                '${presetLocation.lat.toStringAsFixed(4)}, '
                                '${presetLocation.lng.toStringAsFixed(4)}',
                                style: AppTextStyles.bodySecondary(
                                  context,
                                ).copyWith(color: AppColors.accent),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => ref
                                  .read(mapCreateLocationProvider.notifier)
                                  .clear(),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: AppColors.accent.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // ─ Foto: elemento protagonista ───────────────────────────
                    _buildPhotoPicker(context, isDark),

                    const SizedBox(height: 24),

                    // ─ Testo, bordo sottile ma niente card/blur ───────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        minLines: 3,
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(fontSize: 15, height: 1.4),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          hintText:
                              'Scrivi qualcosa che le persone scopriranno…',
                          hintStyle: AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(fontSize: 15),
                        ),
                      ),
                    ),

                    // ─ Mood ───────────────────────────────────────────────────
                    const SizedBox(height: 28),
                    Text('Mood', style: AppTextStyles.headline(context)),
                    const SizedBox(height: 14),
                    _buildMoodPicker(context),

                    // ─ Visibilità ─────────────────────────────────────────────
                    const SizedBox(height: 28),
                    Text(
                      'Chi può vederlo?',
                      style: AppTextStyles.headline(context),
                    ),
                    const SizedBox(height: 14),
                    _buildVisibilityPill(context, isDark),

                    // ─ Tag persone (opzionale) ────────────────────────────────
                    const SizedBox(height: 28),
                    Text(
                      'Tagga la tua cerchia',
                      style: AppTextStyles.headline(context),
                    ),
                    const SizedBox(height: 14),
                    _buildTagPicker(context, isDark),

                    // ─ Evento (opzionale) ─────────────────────────────────────
                    _buildEventPicker(context),

                    // ─ Localizzazione ─────────────────────────────────────────
                    const SizedBox(height: 28),
                    Text('Dove sei?', style: AppTextStyles.headline(context)),
                    const SizedBox(height: 14),
                    if (_selectedEvent != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentSecondary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: AppColors.accentSecondary.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 15,
                              color: AppColors.accentSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedEvent!.venueName,
                                style: AppTextStyles.bodySecondary(
                                  context,
                                ).copyWith(color: AppColors.accentSecondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          _LocationChip(
                            icon: Icons.my_location_rounded,
                            label: 'GPS',
                            selected: _locationMode == _LocationMode.gps,
                            isDark: isDark,
                            onTap: () => setState(() {
                              _locationMode = _LocationMode.gps;
                              _searchedLat = null;
                              _searchedLng = null;
                              _searchedLabel = null;
                              _locationSearchController.clear();
                            }),
                          ),
                          const SizedBox(width: 10),
                          _LocationChip(
                            icon: Icons.search_rounded,
                            label: 'Cerca via',
                            selected: _locationMode == _LocationMode.search,
                            isDark: isDark,
                            onTap: () => setState(
                              () => _locationMode = _LocationMode.search,
                            ),
                          ),
                        ],
                      ),
                      if (_locationMode == _LocationMode.search) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _locationSearchController,
                                style: AppTextStyles.body(context),
                                textInputAction: TextInputAction.search,
                                onChanged: _onSearchChanged,
                                onSubmitted: (_) => _searchLocation(),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  hintText: 'Es. Via Roma 1, Milano',
                                  hintStyle: AppTextStyles.bodySecondary(
                                    context,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _searchingLocation
                                  ? null
                                  : _searchLocation,
                              child: _searchingLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: AppColors.accent,
                                    ),
                            ),
                          ],
                        ),
                        if (_suggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.lg,
                                  ),
                                  border: Border.all(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: _suggestions.asMap().entries.map((
                                    entry,
                                  ) {
                                    final i = entry.key;
                                    final s = entry.value;
                                    return Column(
                                      children: [
                                        InkWell(
                                          onTap: () => _pickSuggestion(s),
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.lg,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 11,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.location_on_outlined,
                                                  size: 15,
                                                  color: AppColors.accent,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    s.label,
                                                    style: AppTextStyles.body(
                                                      context,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (i < _suggestions.length - 1)
                                          Divider(
                                            height: 1,
                                            color: AppColors.accent.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (_searchedLabel != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.accent.withValues(alpha: 0.14),
                                  AppColors.accentSecondary.withValues(
                                    alpha: 0.14,
                                  ),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 15,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _searchedLabel!,
                                    style: AppTextStyles.bodySecondary(
                                      context,
                                    ).copyWith(color: AppColors.accent),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _searchedLat = null;
                                    _searchedLng = null;
                                    _searchedLabel = null;
                                  }),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: AppColors.accent.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],

                    const SizedBox(height: 36),

                    // ─ Drop button ────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: GradientButton(
                        onPressed: _saving ? null : _drop,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(width: 8),
                                  Text(
                                    'Lascia il drop',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Photo picker: hero element ───────────────────────────────────────────

  Widget _buildPhotoPicker(BuildContext context, bool isDark) {
    final hasImage = _imageBytes != null;
    return Builder(
      builder: (buttonContext) => GestureDetector(
        onTap: () => _pickImage(buttonContext),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: hasImage ? 260 : 180,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: hasImage
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.14),
                      AppColors.accentSecondary.withValues(alpha: 0.14),
                    ],
                  ),
            border: Border.all(
              color: hasImage
                  ? Colors.transparent
                  : AppColors.accent.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      Uint8List.fromList(_imageBytes!),
                      fit: BoxFit.cover,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.5],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => setState(() => _imageBytes = null),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.35),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.autorenew_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Cambia foto',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accent,
                              AppColors.accentSecondary,
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_rounded,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Aggiungi una foto',
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Obbligatoria per lasciare il drop',
                        style: AppTextStyles.bodySecondary(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Mood picker: colorful scrollable bubbles ─────────────────────────────

  Widget _buildMoodPicker(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: DropMood.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final mood = DropMood.values[i];
          final selected = _mood == mood;
          return GestureDetector(
            onTap: () => setState(() => _mood = mood),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  // Not easeOutBack: it overshoots past the target, which
                  // briefly drives the animated boxShadow's blurRadius
                  // negative and crashes the renderer.
                  curve: Curves.easeOutCubic,
                  width: selected ? 56 : 48,
                  height: selected ? 56 : 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              mood.color,
                              mood.color.withValues(alpha: 0.6),
                            ],
                          )
                        : null,
                    color: selected ? null : mood.color.withValues(alpha: 0.12),
                    border: Border.all(
                      color: mood.color.withValues(alpha: selected ? 0.9 : 0.3),
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: mood.color.withValues(alpha: 0.45),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    mood.icon,
                    size: selected ? 26 : 22,
                    color: selected ? Colors.white : mood.color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mood.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? mood.color
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Visibility: sliding pill selector ────────────────────────────────────

  Widget _buildVisibilityPill(BuildContext context, bool isDark) {
    final locked = _selectedEvent != null;
    final values = DropVisibility.values;
    final count = values.length;
    final index = values.indexOf(locked ? DropVisibility.public : _visibility);

    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: locked,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 52,
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
                      count > 1 ? 2 * index / (count - 1) - 1 : 0,
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / count,
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
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final v in values)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _visibility = v),
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      v.icon,
                                      size: 15,
                                      color: v == values[index]
                                          ? Colors.white
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      v.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: v == values[index]
                                            ? Colors.white
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
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

  // ─── Tag persone (opzionale) ──────────────────────────────────────────────

  Future<void> _openTagPicker() async {
    final result = await showModalBottomSheet<List<ProfileModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black.withValues(alpha: 0.18),
      builder: (_) => _TagPeopleSheet(initiallySelected: _taggedUsers),
    );
    if (result != null && mounted) {
      setState(() => _taggedUsers = result);
    }
  }

  Widget _buildTagPicker(BuildContext context, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final user in _taggedUsers)
          _TaggedUserChip(
            user: user,
            onRemove: () => setState(
              () => _taggedUsers = _taggedUsers
                  .where((u) => u.id != user.id)
                  .toList(),
            ),
          ),
        _AddTagChip(hasTags: _taggedUsers.isNotEmpty, onTap: _openTagPicker),
      ],
    );
  }

  // ─── Evento vicino (opzionale) ────────────────────────────────────────────

  Widget _buildEventPicker(BuildContext context) {
    final coords = _eventQueryCoords;
    if (coords == null) return const SizedBox.shrink();

    final eventsAsync = ref.watch(nearbyActiveEventsProvider(coords));
    final events = eventsAsync.asData?.value ?? const <EventModel>[];
    if (events.isEmpty) return const SizedBox.shrink();

    // Se l'evento selezionato non è più tra quelli disponibili, deseleziona.
    if (_selectedEvent != null &&
        !events.any((e) => e.id == _selectedEvent!.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedEvent = null);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Text('Fai parte di un evento?', style: AppTextStyles.headline(context)),
        const SizedBox(height: 14),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final event = events[i];
              final selected = _selectedEvent?.id == event.id;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedEvent = selected ? null : event;
                  if (_selectedEvent != null) {
                    _visibility = DropVisibility.public;
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: [
                              AppColors.accent,
                              AppColors.accentSecondary,
                            ],
                          )
                        : null,
                    color: selected
                        ? null
                        : AppColors.accentSecondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.accentSecondary.withValues(
                        alpha: selected ? 0.9 : 0.3,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : AppColors.accentSecondary,
                        ),
                      ),
                      Text(
                        event.venueName,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.accentSecondary.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_selectedEvent != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: AppColors.accentSecondary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Il drop resterà visibile a tutti in questa categoria per '
                  'tutta la durata dell\'evento. Al termine, sarà visibile solo '
                  'a te e alla tua cerchia — lo ritroverai comunque sul tuo profilo.',
                  style: AppTextStyles.bodySecondary(
                    context,
                  ).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Tag people sheet: multi-select dalla cerchia ─────────────────────────────

class _TagPeopleSheet extends ConsumerStatefulWidget {
  const _TagPeopleSheet({required this.initiallySelected});
  final List<ProfileModel> initiallySelected;

  @override
  ConsumerState<_TagPeopleSheet> createState() => _TagPeopleSheetState();
}

class _TagPeopleSheetState extends ConsumerState<_TagPeopleSheet> {
  late final Map<String, ProfileModel> _selected = {
    for (final u in widget.initiallySelected) u.id: u,
  };
  String _query = '';

  void _toggle(ProfileModel user) {
    setState(() {
      if (_selected.containsKey(user.id)) {
        _selected.remove(user.id);
      } else {
        _selected[user.id] = user;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionsAsync = ref.watch(myConnectionsProvider);

    return EchoBottomSheet(
      height: MediaQuery.of(context).size.height * 0.75,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text('Tagga persone', style: AppTextStyles.headline(context)),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.values.toList()),
                    child: Text('Fatto (${_selected.length})'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: AppTextStyles.body(context),
                decoration: InputDecoration(
                  hintText: 'Cerca nella tua cerchia',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
            Expanded(
              child: connectionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Errore nel caricamento',
                    style: AppTextStyles.bodySecondary(context),
                  ),
                ),
                data: (connections) {
                  final filtered = connections.where((u) {
                    if (_query.isEmpty) return true;
                    final q = _query.toLowerCase();
                    return u.username.toLowerCase().contains(q) ||
                        u.displayName.toLowerCase().contains(q);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        connections.isEmpty
                            ? 'Non hai ancora collegamenti da taggare.'
                            : 'Nessun utente trovato.',
                        style: AppTextStyles.bodySecondary(context),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final user = filtered[i];
                      final name = user.displayName.isNotEmpty
                          ? user.displayName
                          : user.username;
                      final checked = _selected.containsKey(user.id);
                      return ListTile(
                        onTap: () => _toggle(user),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.accent.withValues(
                            alpha: 0.15,
                          ),
                          backgroundImage: user.avatarUrl != null
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(name, style: AppTextStyles.body(context)),
                        subtitle: Text(
                          '@${user.username}',
                          style: AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(fontSize: 12),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: checked
                              ? AppColors.accent
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tagged user chip ─────────────────────────────────────────────────────────

class _TaggedUserChip extends StatelessWidget {
  const _TaggedUserChip({required this.user, required this.onRemove});

  final ProfileModel user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty
        ? user.displayName
        : user.username;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: user.avatarUrl != null
                ? CachedNetworkImageProvider(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.accent.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add tag chip ─────────────────────────────────────────────────────────────

class _AddTagChip extends StatelessWidget {
  const _AddTagChip({required this.hasTags, required this.onTap});

  final bool hasTags;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: AppColors.accentSecondary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_add_alt_1_rounded,
              size: 15,
              color: AppColors.accentSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              hasTags ? 'Modifica' : 'Tagga persone',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accentSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Location chip ────────────────────────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: isDark ? 0.05 : 0.4),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.accent,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Location helpers ─────────────────────────────────────────────────────────

enum _LocationMode { gps, search }

class _LocationSuggestion {
  final double lat, lng;
  final String label;
  const _LocationSuggestion(this.lat, this.lng, this.label);
}

// ─── Extension helper ─────────────────────────────────────────────────────────

extension _ToUint8List on List<int> {
  Uint8List toUint8List() => Uint8List.fromList(this);
}
