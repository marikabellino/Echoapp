import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DropRelation { mine, circle, public }

extension DropRelationX on DropRelation {
  Color get color => switch (this) {
    DropRelation.mine => Colors.white,
    DropRelation.circle => AppColors.accent,
    DropRelation.public => AppColors.accentSecondary,
  };

  Color get onColor => switch (this) {
    DropRelation.mine => AppColors.darkBackground,
    DropRelation.circle => Colors.white,
    DropRelation.public => AppColors.darkBackground,
  };

  String get label => switch (this) {
    DropRelation.mine => 'Tuo',
    DropRelation.circle => 'Cerchia',
    DropRelation.public => 'Pubblico',
  };

  IconData get icon => switch (this) {
    DropRelation.mine => Icons.person_rounded,
    DropRelation.circle => Icons.people_alt_rounded,
    DropRelation.public => Icons.public_rounded,
  };
}

final circleIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final list = ref.watch(myConnectionsProvider).asData?.value;
  return {for (final p in list ?? const []) p.id};
});

DropRelation relationOf(
  DropModel drop, {
  required String? myId,
  required Set<String> circleIds,
}) {
  if (myId != null && drop.userId == myId) return DropRelation.mine;
  if (circleIds.contains(drop.userId) ||
      drop.visibility == DropVisibility.circle) {
    return DropRelation.circle;
  }
  return DropRelation.public;
}

DropRelation watchRelation(WidgetRef ref, DropModel drop) => relationOf(
  drop,
  myId: ref.watch(currentUserProvider)?.id,
  circleIds: ref.watch(circleIdsProvider),
);
