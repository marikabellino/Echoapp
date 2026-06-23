import 'dart:async';
import 'dart:typed_data';

import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/memory/domain/models/memory_model.dart';
import 'package:echo/features/memory/providers/memory_provider.dart';
import 'package:echo/features/profile/providers/profile_provider.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_card.dart';
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
  MemoryMood _mood = MemoryMood.echo;
  MemoryVisibility _visibility = MemoryVisibility.public;
  bool _saving = false;
  // bool _generatingAi = false; // TODO: AI v2
  String? _aiCaption;
  List<int>? _imageBytes;

  _LocationMode _locationMode = _LocationMode.gps;
  double? _searchedLat;
  double? _searchedLng;
  String? _searchedLabel;
  bool _searchingLocation = false;
  List<_LocationSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _locationSearchController.dispose();
    super.dispose();
  }

  // TODO: AI v2 — _generateCaption e _suggestMood rimossi dalla UI

  // ─── Image picker ────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final source = await _showImageSourceSheet();
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

  Future<ImageSource?> _showImageSourceSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageSourceSheet(isDark: isDark),
    );
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _drop() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnack('Scrivi qualcosa prima di lasciare un ricordo!');
      return;
    }
    if (_imageBytes == null) {
      _showSnack('Aggiungi una foto al ricordo.', type: EchoToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(memoryRepositoryProvider);
      final preset = ref.read(mapCreateLocationProvider);

      double lat, lng;
      String? locationName;
      if (preset != null) {
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
        imageUrl = await repo.uploadMemoryImage(
          _imageBytes!.toUint8List(),
        );
      }

      await repo.createMemory(
        description: text,
        mood: _mood,
        latitude: lat,
        longitude: lng,
        locationName: locationName,
        imageUrl: imageUrl,
        aiCaption: _aiCaption,
        visibility: _visibility,
      );

      final userId = ref.read(currentUserProvider)?.id;
      ref.invalidate(discoverProvider);
      if (userId != null) ref.invalidate(userMemoriesProvider(userId));
      ref.invalidate(currentProfileProvider);

      if (mounted) {
        _controller.clear();
        setState(() {
          _mood = MemoryMood.echo;
          _visibility = MemoryVisibility.public;
          _aiCaption = null;
          _imageBytes = null;
          _locationMode = _LocationMode.gps;
          _searchedLat = null;
          _searchedLng = null;
          _searchedLabel = null;
          _suggestions = [];
          _locationSearchController.clear();
        });
        _showSnack('Ricordo lasciato nel mondo.', type: EchoToastType.success);
        ref.read(shellIndexProvider.notifier).setIndex(1);
      }
    } catch (e) {
      if (mounted) { _showSnack('Errore: $e', type: EchoToastType.error); }
    } finally {
      if (mounted) { setState(() => _saving = false); }
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
      final marks = await gc.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final m = marks.first;
        return [m.street, m.locality, m.country]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
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
    _debounce = Timer(const Duration(milliseconds: 600), () => _fetchSuggestions(value.trim()));
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _searchingLocation = true);
    try {
      final encoded = Uri.encodeComponent(query);
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
        '?access_token=${AppConstants.mapboxToken}'
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
          final marks = await gc.placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (marks.isNotEmpty) {
            final m = marks.first;
            label = [m.street, m.locality, m.country]
                .where((s) => s != null && s.isNotEmpty)
                .join(', ');
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
      if (mounted) _showSnack('Indirizzo non trovato', type: EchoToastType.error);
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
    final presetLocation = ref.watch(mapCreateLocationProvider);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [
                        Color(0xFF100F1C),
                        Color(0xFF181528),
                        Color(0xFF100E1A),
                      ]
                    : const [
                        Color(0xFFF3F1FC),
                        Color(0xFFE9E6F7),
                        Color(0xFFF2F0FB),
                      ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lascia un ricordo',
                    style: AppTextStyles.displayLarge(context),
                  ),
                  const SizedBox(height: 8),
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
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Posizione dalla mappa: '
                              '${presetLocation.lat.toStringAsFixed(4)}, '
                              '${presetLocation.lng.toStringAsFixed(4)}',
                              style: AppTextStyles.bodySecondary(context)
                                  .copyWith(color: AppColors.primary),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => ref
                                .read(mapCreateLocationProvider.notifier)
                                .clear(),
                            child: Icon(
                              Icons.close,
                              size: 15,
                              color: AppColors.primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // ─ Text input ────────────────────────────────────────────────
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _controller,
                            maxLines: 5,
                            style: AppTextStyles.body(context),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText:
                                  'Scrivi qualcosa che le persone scopriranno...',
                            ),
                          ),
                          if (_imageBytes != null) ...[
                            const SizedBox(height: 12),
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    Uint8List.fromList(_imageBytes!),
                                    width: double.infinity,
                                    height: 180,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _imageBytes = null),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const Divider(height: 24),
                          Row(
                            children: [
                              // TODO: AI v2 — Mood AI e Didascalia AI
                              // Image
                              _ActionButton(
                                icon: _imageBytes != null
                                    ? Icons.image_rounded
                                    : Icons.image_outlined,
                                label: _imageBytes != null ? 'Foto ✓' : 'Foto *',
                                selected: _imageBytes != null,
                                isDark: isDark,
                                onTap: _pickImage,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // TODO: AI v2 — AI caption preview rimossa

                  // ─ Mood selector ─────────────────────────────────────────────
                  const SizedBox(height: 28),
                  Text('Mood', style: AppTextStyles.headline(context)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: MemoryMood.values.map((mood) {
                      final selected = _mood == mood;
                      return GestureDetector(
                        onTap: () => setState(() => _mood = mood),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: selected
                                ? mood.color.withValues(alpha: 0.18)
                                : Colors.white.withValues(
                                    alpha: isDark ? 0.05 : 0.4,
                                  ),
                            border: Border.all(
                              color: selected
                                  ? mood.color
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: mood.color.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      spreadRadius: 0,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            mood.label,
                            style: AppTextStyles.body(context).copyWith(
                              color: selected ? mood.color : null,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // ─ Visibilità ────────────────────────────────────────────────
                  const SizedBox(height: 28),
                  Text('Visibilità', style: AppTextStyles.headline(context)),
                  const SizedBox(height: 16),
                  Row(
                    children: MemoryVisibility.values.map((v) {
                      final selected = _visibility == v;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: v != MemoryVisibility.private ? 8 : 0,
                          ),
                          child: GestureDetector(
                            onTap: () => setState(() => _visibility = v),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: selected
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : Colors.white.withValues(
                                        alpha: isDark ? 0.05 : 0.4,
                                      ),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.accent
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    v.icon,
                                    size: 18,
                                    color: selected
                                        ? AppColors.accent
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    v.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: selected
                                          ? AppColors.accent
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
                      );
                    }).toList(),
                  ),

                  // ─ Localizzazione ────────────────────────────────────────────
                  const SizedBox(height: 28),
                  Text('Localizzazione', style: AppTextStyles.headline(context)),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _LocationChip(
                                icon: Icons.my_location_outlined,
                                label: 'Posizione GPS',
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
                                icon: Icons.search,
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
                                      hintText: 'Es. Via Roma 1, Milano',
                                      hintStyle: AppTextStyles.bodySecondary(context),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _searchingLocation ? null : _searchLocation,
                                  child: _searchingLocation
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 1.5),
                                        )
                                      : Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                          color: AppColors.accent,
                                        ),
                                ),
                              ],
                            ),
                            if (_suggestions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.accent.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Column(
                                  children: _suggestions.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final s = entry.value;
                                    return Column(
                                      children: [
                                        InkWell(
                                          onTap: () => _pickSuggestion(s),
                                          borderRadius: BorderRadius.circular(12),
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
                                                    style: AppTextStyles.body(context),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (i < _suggestions.length - 1)
                                          Divider(
                                            height: 1,
                                            color: AppColors.accent.withValues(alpha: 0.08),
                                          ),
                                      ],
                                    );
                                  }).toList(),
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
                                  color: AppColors.accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.accent.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _searchedLabel!,
                                        style: AppTextStyles.bodySecondary(context)
                                            .copyWith(color: AppColors.accent),
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
                                        color: AppColors.accent.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ─ Drop button ───────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _drop,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Lascia il ricordo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.isDark = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool isDark;

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
            Icon(
              icon,
              size: 14,
              color: AppColors.accent,
            ),
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

// ─── Image source sheet ───────────────────────────────────────────────────────

class _ImageSourceSheet extends StatelessWidget {
  final bool isDark;

  const _ImageSourceSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            GlassCard(
              child: Column(
                children: [
                  _SheetOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Fotocamera',
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  _SheetOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Galleria',
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: _SheetOption(
                icon: Icons.close,
                label: 'Annulla',
                onTap: () => Navigator.pop(context),
                accent: false,
                centered: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool centered;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = true,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.accent
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: AppTextStyles.body(context).copyWith(
                color: color,
                fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Extension helper ─────────────────────────────────────────────────────────

extension _ToUint8List on List<int> {
  Uint8List toUint8List() => Uint8List.fromList(this);
}
