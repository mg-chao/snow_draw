import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../../../../utils/selection_calculator.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';
import 'elbow_constants.dart';
import 'elbow_fixed_segment.dart';
import 'elbow_geometry.dart';
import 'elbow_router.dart';

part 'elbow_edit_endpoint_drag.dart';
part 'elbow_edit_fixed_segments.dart';
part 'elbow_edit_geometry.dart';
part 'elbow_edit_perpendicular.dart';
part 'elbow_edit_pipeline.dart';
part 'elbow_edit_routing.dart';

/// Elbow arrow editing entry points.
/// Output of elbow edit computation (local points + fixed segment updates).
@immutable
final class ElbowEditResult {
  const ElbowEditResult({
    required this.localPoints,
    required this.fixedSegments,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> localPoints;
  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;
}

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) =>
    // Route the edit through a step-based pipeline for clarity.
    _ElbowEditPipeline(
      element: element,
      data: data,
      elementsById: elementsById,
      localPointsOverride: localPointsOverride,
      fixedSegmentsOverride: fixedSegmentsOverride,
      startBindingOverride: startBindingOverride,
      endBindingOverride: endBindingOverride,
    ).run();

/// Transforms fixed segments when the owning element is resized/rotated.
List<ElbowFixedSegment>? transformFixedSegments({
  required List<ElbowFixedSegment>? segments,
  required DrawRect oldRect,
  required DrawRect newRect,
  required double rotation,
}) {
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final newSpace = ElementSpace(rotation: rotation, origin: newRect.center);
  final transformed = segments
      .map((segment) {
        final worldStart = oldSpace.toWorld(segment.start);
        final worldEnd = oldSpace.toWorld(segment.end);
        return segment.copyWith(
          start: newSpace.fromWorld(worldStart),
          end: newSpace.fromWorld(worldEnd),
        );
      })
      .toList(growable: false);
  return List<ElbowFixedSegment>.unmodifiable(transformed);
}
