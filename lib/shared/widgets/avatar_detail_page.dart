import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';

/// Full-screen avatar preview — large circle with a round glass back button,
/// matching the style already used across the app.
class AvatarDetailPage extends StatelessWidget {
  const AvatarDetailPage({super.key, required this.imageUrl, this.heroTag});

  final String imageUrl;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.82;

    Widget circle = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, _) => const ColoredBox(color: Colors.white10),
          errorWidget: (_, _, _) => const ColoredBox(color: Colors.white10),
        ),
      ),
    );

    if (heroTag != null) {
      circle = Hero(tag: heroTag!, child: circle);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: circle),
            Positioned(
              left: 12,
              top: 4,
              child: GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
