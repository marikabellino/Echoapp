import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:flutter/material.dart';

class DropMarker extends StatefulWidget {
  const DropMarker({
    super.key,
    required this.mood,
    this.selected = false,
    this.glowIntensity = 1.0,
    this.markerOpacity = 1.0,
    this.sizeMultiplier = 1.0,
  });

  final DropMood mood;
  final bool selected;
  final double glowIntensity;
  final double markerOpacity;
  final double sizeMultiplier;

  @override
  State<DropMarker> createState() => _DropMarkerState();
}

class _DropMarkerState extends State<DropMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.mood.color;
    final coreSize =
        (widget.selected ? 20.0 : 14.0) * widget.sizeMultiplier;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) {
        final p = _pulse.value; // 0 → 1 → 0

        return Opacity(
          opacity: widget.markerOpacity,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring
                Transform.scale(
                  scale: 1.0 + p * 0.65,
                  child: Container(
                    width: coreSize + 10,
                    height: coreSize + 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(
                        alpha: (0.22 - p * 0.20) * widget.glowIntensity,
                      ),
                    ),
                  ),
                ),

                // Core dot
                Container(
                  width: coreSize,
                  height: coreSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.45),
                      radius: 0.85,
                      colors: [
                        Color.lerp(Colors.white, color, 0.45)!,
                        color,
                        Color.lerp(color, Colors.black, 0.18)!,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    border: widget.selected
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.88),
                            width: 2.0,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(
                          alpha: (0.65 + p * 0.20) * widget.glowIntensity,
                        ),
                        blurRadius: (widget.selected ? 18 : 12) *
                            widget.glowIntensity,
                        spreadRadius: widget.selected ? 2 : 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
