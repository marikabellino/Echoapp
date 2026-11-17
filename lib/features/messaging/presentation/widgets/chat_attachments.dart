import 'package:echo/features/drop/presentation/widgets/relation_badge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/constants/app_constants.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:echo/features/drop/presentation/pages/drop_detail_page.dart';
import 'package:echo/features/drop/providers/drop_provider.dart';
import 'package:echo/features/profile/presentation/widgets/profile_widgets.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

typedef ChatAttachment = ({
  String? dropId,
  double? lat,
  double? lng,
  String? label,
});

Future<ChatAttachment?> showChatAttachSheet(BuildContext context) {
  return showModalBottomSheet<ChatAttachment>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatefulWidget {
  const _AttachSheet();

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  bool _locating = false;

  Future<void> _shareLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permesso posizione negato');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).catchError((_) async => (await Geolocator.getLastKnownPosition())!);
      String? label;
      try {
        final marks = await gc.placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty) {
          final m = marks.first;
          final parts = [
            (m.street?.isNotEmpty ?? false) ? m.street : m.name,
            m.locality,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
          if (parts.isNotEmpty) label = parts.join(', ');
        }
      } catch (_) {}
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop<ChatAttachment>((
        dropId: null,
        lat: pos.latitude,
        lng: pos.longitude,
        label: label,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      EchoToast.show(
        context,
        'Non riesco a rilevare la posizione',
        type: EchoToastType.error,
      );
    }
  }

  Future<void> _shareDrop() async {
    final drop = await Navigator.of(context).push<DropModel>(
      MaterialPageRoute(builder: (_) => const _MyDropsPicker()),
    );
    if (drop == null || !mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).pop<ChatAttachment>((dropId: drop.id, lat: null, lng: null, label: null));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AttachOption(
                  icon: Icons.near_me_rounded,
                  title: 'Dove sono',
                  subtitle: 'Ci vediamo qui',
                  gradient: AppColors.brandGradient,
                  loading: _locating,
                  onTap: _locating ? null : _shareLocation,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AttachOption(
                  icon: Icons.grid_view_rounded,
                  title: 'Un mio drop',
                  subtitle: 'Mandalo in chat',
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.moodSecret, AppColors.moodLost],
                  ),
                  onTap: _locating ? null : _shareDrop,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 132,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 22),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.bodySecondary(context)),
          ],
        ),
      ),
    );
  }
}

class _MyDropsPicker extends ConsumerWidget {
  const _MyDropsPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider)?.id ?? '';
    final drops = ref.watch(userDropsProvider(me));
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        leadingWidth: 64,
        title: Text(
          'Scegli un drop',
          style: AppTextStyles.headline(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: drops.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Errore nel caricamento',
            style: AppTextStyles.bodySecondary(context),
          ),
        ),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(
                  'Non hai ancora lasciato drop.',
                  style: AppTextStyles.bodySecondary(context),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(3),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) =>
                    DropGridTile(
                          drop: list[i],
                          onTap: () => Navigator.of(context).pop(list[i]),
                          onLongPress: () => openDropDetail(context, list[i]),
                        )
                        .animate(delay: (25 * (i < 15 ? i : 15)).ms)
                        .fadeIn(duration: 280.ms),
              ),
      ),
    );
  }
}

class SharedDropBubble extends ConsumerWidget {
  const SharedDropBubble({super.key, required this.dropId});
  final String dropId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dropByIdProvider(dropId));
    const width = 220.0;

    return async.when(
      loading: () => Container(
        width: width,
        height: 230,
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      error: (_, _) => _unavailable(),
      data: (drop) {
        if (drop == null) return _unavailable();
        return GestureDetector(
          onTap: () => openDropDetail(context, drop),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: width,
              color: AppColors.darkSurfaceLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 170,
                    width: width,
                    child: drop.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: drop.imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 500,
                            errorWidget: (_, _, _) => const DropPlaceholder(),
                          )
                        : const DropPlaceholder(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              size: 13,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              drop.author != null
                                  ? '@${drop.author!.username}'
                                  : 'Drop',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (drop.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            drop.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (drop.displayLocation != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  drop.displayLocation!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _unavailable() => Container(
    width: 220,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.darkSurfaceLight,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        Icon(
          Icons.visibility_off_outlined,
          size: 16,
          color: Colors.white.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Drop non disponibile',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
      ],
    ),
  );
}

class LocationBubble extends StatelessWidget {
  const LocationBubble({
    super.key,
    required this.lat,
    required this.lng,
    required this.label,
    required this.isMine,
  });

  final double lat;
  final double lng;
  final String? label;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocationPreviewPage(lat: lat, lng: lng, label: label),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 220,
          color: AppColors.darkSurfaceLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                width: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF2A1A2E), Color(0xFF1A1420)],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _GridPainter()),
                    ),
                    Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent.withValues(alpha: 0.18),
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat())
                        .scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1.2, 1.2),
                          duration: 1600.ms,
                          curve: Curves.easeOut,
                        )
                        .fadeOut(duration: 1600.ms),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                      child: const Icon(
                        Icons.near_me_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMine ? 'Sono qui' : 'È qui',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        label!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Apri sulla mappa',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x + 30, size.height), p);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 8), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LocationPreviewPage extends StatelessWidget {
  const LocationPreviewPage({
    super.key,
    required this.lat,
    required this.lng,
    this.label,
  });

  final double lat;
  final double lng;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          MapLibreMap(
            styleString: AppConstants.maptilerDarkStyle,
            initialCameraPosition: CameraPosition(
              target: LatLng(lat, lng),
              zoom: 15,
            ),
            compassEnabled: false,
            myLocationEnabled: true,
            onStyleLoadedCallback: () {},
            onMapCreated: (c) async {
              await Future<void>.delayed(const Duration(milliseconds: 600));
              await c.addCircle(
                CircleOptions(
                  geometry: LatLng(lat, lng),
                  circleRadius: 10,
                  circleColor: '#FF3D7F',
                  circleStrokeWidth: 3,
                  circleStrokeColor: '#FFFFFF',
                ),
              );
            },
          ),
          Positioned(
            top: top + 8,
            left: 12,
            child: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom + 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkBackground.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.brandGradient,
                    ),
                    child: const Icon(
                      Icons.near_me_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Posizione condivisa',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          label ??
                              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySecondary(context),
                        ),
                      ],
                    ),
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
