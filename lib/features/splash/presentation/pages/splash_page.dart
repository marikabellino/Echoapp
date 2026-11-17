import 'package:echo/shared/widgets/brand/mingle_splash.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pagina di splash standalone: riproduce [MingleSplash] e poi va alla home.
/// All'avvio dell'app lo splash è già mostrato da `LaunchIntro` in app.dart.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MingleSplash(
        onFinished: () {
          if (context.mounted) context.go('/');
        },
      ),
    );
  }
}
