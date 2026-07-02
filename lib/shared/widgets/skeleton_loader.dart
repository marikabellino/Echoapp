import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

// ─── Shimmer engine ───────────────────────────────────────────────────────────

/// Wraps [child] with a left-to-right shimmer sweep using a single
/// AnimationController, so all boxes inside pulse in sync.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, required this.child});
  final Widget child;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0);
    final glow = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final x = -1.5 + 3.0 * _ctrl.value;
          return LinearGradient(
            colors: [base, glow, base],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
          ).createShader(bounds);
        },
        child: child!,
      ),
    );
  }
}

// ─── Primitives ───────────────────────────────────────────────────────────────

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8.0,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: size, height: size, radius: size / 2);
  }
}

// ─── Conversation list (Messages page) ───────────────────────────────────────

class SkeletonConversationList extends StatelessWidget {
  const SkeletonConversationList({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonLoader(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF131720).withValues(alpha: 0.5)
                : const Color(0xFFF0EFF8).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              const SkeletonCircle(size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SkeletonBox(width: 120, height: 14, radius: 6),
                        const Spacer(),
                        const SkeletonBox(width: 36, height: 11, radius: 4),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const SkeletonBox(height: 12, radius: 4),
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

// ─── Profile page (full-page load) ───────────────────────────────────────────

class SkeletonProfilePage extends StatelessWidget {
  const SkeletonProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: avatar + name/stats + icons
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonCircle(size: 76),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        const SkeletonBox(width: 140, height: 22, radius: 8),
                        const SizedBox(height: 8),
                        const SkeletonBox(width: 90, height: 14, radius: 6),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _StatBlock(),
                            const SizedBox(width: 28),
                            _StatBlock(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SkeletonCircle(size: 36),
                  const SizedBox(width: 4),
                  const SkeletonCircle(size: 36),
                ],
              ),
              const SizedBox(height: 16),
              // Bio lines
              const SkeletonBox(height: 14, radius: 6),
              const SizedBox(height: 6),
              const SkeletonBox(width: 200, height: 14, radius: 6),
              const SizedBox(height: 20),
              // Edit profile button
              const SkeletonBox(height: 46, radius: 12),
              const SizedBox(height: 28),
              // Section title
              const SkeletonBox(width: 160, height: 22, radius: 8),
              const SizedBox(height: 16),
              // Memories grid (no extra loader — parent has one)
              const SkeletonMemoriesGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        SkeletonBox(width: 40, height: 20, radius: 6),
        SizedBox(height: 4),
        SkeletonBox(width: 50, height: 12, radius: 4),
      ],
    );
  }
}

// ─── Memories grid ────────────────────────────────────────────────────────────

/// Pass [wrapInLoader] = true when this widget is used standalone (not already
/// inside a [SkeletonLoader] parent).
class SkeletonMemoriesGrid extends StatelessWidget {
  const SkeletonMemoriesGrid({super.key, this.wrapInLoader = false});
  final bool wrapInLoader;

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => const SkeletonBox(height: double.infinity, radius: 12),
    );
    return wrapInLoader ? SkeletonLoader(child: grid) : grid;
  }
}

// ─── Comment list ─────────────────────────────────────────────────────────────

class SkeletonCommentList extends StatelessWidget {
  const SkeletonCommentList({super.key, this.itemCount = 4});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 20),
        itemBuilder: (_, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonCircle(size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 100, height: 13, radius: 5),
                  SizedBox(height: 6),
                  SkeletonBox(height: 13, radius: 5),
                  SizedBox(height: 4),
                  SkeletonBox(width: 160, height: 13, radius: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User list (blocked users, connections, requests) ────────────────────────

class SkeletonUserList extends StatelessWidget {
  const SkeletonUserList({
    super.key,
    this.itemCount = 7,
    this.showTrailing = false,
  });
  final int itemCount;
  final bool showTrailing;

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const SkeletonCircle(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 130, height: 14, radius: 6),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 12, radius: 4),
                  ],
                ),
              ),
              if (showTrailing) ...[
                const SizedBox(width: 12),
                const SkeletonBox(width: 60, height: 28, radius: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search user list (Discover — GlassCard style) ───────────────────────────

class SkeletonSearchUserList extends StatelessWidget {
  const SkeletonSearchUserList({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonLoader(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF131720).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              const SkeletonCircle(size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 120, height: 14, radius: 6),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 12, radius: 4),
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

// ─── Memory feed (Discover) ───────────────────────────────────────────────────

class SkeletonMemoryFeed extends StatelessWidget {
  const SkeletonMemoryFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonLoader(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 20),
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF131720).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image area
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SkeletonBox(width: 64, height: 24, radius: 12),
                        const Spacer(),
                        const SkeletonCircle(size: 22),
                        const SizedBox(width: 6),
                        const SkeletonBox(width: 72, height: 14, radius: 6),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SkeletonBox(height: 14, radius: 6),
                    const SizedBox(height: 6),
                    const SkeletonBox(height: 14, radius: 6),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 180, height: 14, radius: 6),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        SkeletonBox(width: 80, height: 12, radius: 4),
                        Spacer(),
                        SkeletonBox(width: 60, height: 12, radius: 4),
                      ],
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

// ─── Chat messages ────────────────────────────────────────────────────────────

class SkeletonChatMessages extends StatelessWidget {
  const SkeletonChatMessages({super.key});

  @override
  Widget build(BuildContext context) {
    const bubbles = [
      (isMe: false, width: 180.0),
      (isMe: true, width: 140.0),
      (isMe: false, width: 220.0),
      (isMe: true, width: 100.0),
      (isMe: false, width: 160.0),
      (isMe: true, width: 200.0),
      (isMe: false, width: 130.0),
    ];
    return SkeletonLoader(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: bubbles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => Align(
          alignment: bubbles[i].isMe
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: SkeletonBox(
            width: bubbles[i].width,
            height: 40,
            radius: 18,
          ),
        ),
      ),
    );
  }
}
