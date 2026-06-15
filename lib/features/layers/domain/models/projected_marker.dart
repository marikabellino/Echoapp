import 'package:apptest/features/memory/domain/models/memory_model.dart';
import 'package:flutter/painting.dart';

class ProjectedMarker {
  final MemoryModel memory;
  final Offset position;
  final bool visible;
  final double distanceFromCenter;

  const ProjectedMarker({
    required this.memory,
    required this.position,
    required this.visible,
    required this.distanceFromCenter,
  });
}
