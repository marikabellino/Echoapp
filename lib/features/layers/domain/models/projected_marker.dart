import 'package:echo/features/drop/domain/models/drop_model.dart';
import 'package:flutter/painting.dart';

class ProjectedMarker {
  final DropModel drop;
  final Offset position;
  final bool visible;
  final double distanceFromCenter;

  const ProjectedMarker({
    required this.drop,
    required this.position,
    required this.visible,
    required this.distanceFromCenter,
  });
}
