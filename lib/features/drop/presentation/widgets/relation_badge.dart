import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/features/drop/domain/drop_relation.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RelationBadge extends ConsumerWidget {
  const RelationBadge({super.key, required this.drop, this.overlay = false});

  final DropModel drop;
  final bool overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = watchRelation(ref, drop);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: overlay
            ? Colors.black.withValues(alpha: 0.4)
            : rel.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: rel.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: rel.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            rel.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: overlay ? Colors.white : rel.color,
            ),
          ),
        ],
      ),
    );
  }
}

class DropPlaceholder extends StatelessWidget {
  const DropPlaceholder({super.key, this.iconSize = 32});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkSurfaceHigh, AppColors.darkSurface],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.notes_rounded,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
