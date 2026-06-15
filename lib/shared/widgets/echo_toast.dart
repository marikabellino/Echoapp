import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

enum EchoToastType { info, success, error }

class EchoToast {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static _ToastController? _controller;

  static void show(
    BuildContext context,
    String message, {
    EchoToastType type = EchoToastType.info,
  }) {
    _timer?.cancel();

    // Dismiss current toast instantly before showing new one
    if (_controller != null) {
      _controller!.dismiss();
      _entry?.remove();
      _entry = null;
      _controller = null;
    }

    final ctrl = _ToastController();
    _controller = ctrl;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        controller: ctrl,
        onDismissed: () {
          entry.remove();
          if (_entry == entry) {
            _entry = null;
            _controller = null;
          }
        },
      ),
    );

    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);

    _timer = Timer(const Duration(milliseconds: 3000), ctrl.dismiss);
  }
}

// ─── Internal controller ──────────────────────────────────────────────────────

class _ToastController {
  VoidCallback? _dismissCallback;

  void _setCallback(VoidCallback cb) => _dismissCallback = cb;

  void dismiss() => _dismissCallback?.call();
}

// ─── Toast widget ─────────────────────────────────────────────────────────────

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.type,
    required this.controller,
    required this.onDismissed,
  });

  final String message;
  final EchoToastType type;
  final _ToastController controller;
  final VoidCallback onDismissed;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideY;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _slideY = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
        reverseCurve: const Interval(0.55, 1.0, curve: Curves.easeIn),
      ),
    );

    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _ctrl.forward();
    widget.controller._setCallback(_triggerDismiss);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _triggerDismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0) {
      setState(() => _dragOffset += d.delta.dy);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset < -30 || d.velocity.pixelsPerSecond.dy < -200) {
      widget.controller.dismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Positioned(
      top: mq.padding.top + 8,
      left: 0,
      right: 0,
      child: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final slideOffset = _slideY.value * 80 + _dragOffset;
            return Transform.translate(
              offset: Offset(0, slideOffset),
              child: Transform.scale(
                scale: _scale.value,
                child: Opacity(opacity: _opacity.value.clamp(0.0, 1.0), child: child),
              ),
            );
          },
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: mq.size.width - 40,
              ),
              child: _Pill(message: widget.message, type: widget.type),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Glass pill ───────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.message, required this.type});

  final String message;
  final EchoToastType type;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (bgColor, borderColor, iconColor, iconData) = switch (type) {
      EchoToastType.success => (
          const Color(0xFF30D158).withValues(alpha: isDark ? 0.14 : 0.10),
          const Color(0xFF30D158).withValues(alpha: 0.35),
          const Color(0xFF30D158),
          Icons.check_circle_outline_rounded,
        ),
      EchoToastType.error => (
          const Color(0xFFFF453A).withValues(alpha: isDark ? 0.14 : 0.10),
          const Color(0xFFFF453A).withValues(alpha: 0.35),
          const Color(0xFFFF453A),
          Icons.error_outline_rounded,
        ),
      EchoToastType.info => (
          (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05)),
          (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08)),
          (isDark
              ? const Color(0xFF7EB8D4)
              : const Color(0xFF5A9FBB)),
          Icons.info_outline_rounded,
        ),
    };

    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black.withValues(alpha: 0.80);

    final surfaceBase = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.78)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.78);

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: Color.alphaBlend(bgColor, surfaceBase),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: borderColor, width: 0.7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, size: 17, color: iconColor),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      letterSpacing: -0.1,
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
