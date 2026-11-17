import 'package:echo/shared/widgets/brand/mingle_splash.dart';
import 'package:flutter/material.dart';

/// Mostra [MingleSplash] sopra l'app al primo avvio (cold start), poi lo
/// dissolve rivelando l'app che nel frattempo si è già caricata sotto.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child});

  final Widget? child;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro> {
  bool _fading = false;
  bool _gone = false;

  void _finish() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _fading = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.child != null) Positioned.fill(child: widget.child!),
        if (!_gone)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _fading,
              child: AnimatedOpacity(
                opacity: _fading ? 0 : 1,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOut,
                onEnd: () => setState(() => _gone = true),
                child: Material(
                  type: MaterialType.transparency,
                  child: MingleSplash(onFinished: _finish),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
