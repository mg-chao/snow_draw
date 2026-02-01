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
import 'elbow_geometry.dart';
import 'elbow_fixed_segment.dart';
import 'elbow_router.dart';

part 'elbow_edit_geometry.dart';
part 'elbow_edit_fixed_segments.dart';
part 'elbow_edit_routing.dart';
part 'elbow_edit_endpoint_drag.dart';
part 'elbow_edit_perpendicular.dart';

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

@immutable
final class _FixedSegmentPathResult {
  const _FixedSegmentPathResult({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;
}

@immutable
final class _PerpendicularAdjustment {
  const _PerpendicularAdjustment({
    required this.points,
    required this.moved,
    required this.inserted,
  });

  final List<DrawPoint> points;
  final bool moved;
  final bool inserted;
}

@immutable
final class _ElbowEditInputs {
  const _ElbowEditInputs({
    required this.element,
    required this.data,
    required this.elementsById,
    required this.basePoints,
    required this.incomingPoints,
    required this.previousFixedSegments,
    required this.fixedSegments,
    required this.startBinding,
    required this.endBinding,
    required this.pointsChanged,
    required this.fixedSegmentsChanged,
    required this.releaseRequested,
  });

  final ElementState element;
  final ArrowData data;
  final Map<String, ElementState> elementsById;
  final List<DrawPoint> basePoints;
  final List<DrawPoint> incomingPoints;
  final List<ElbowFixedSegment> previousFixedSegments;
  final List<ElbowFixedSegment> fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final bool pointsChanged;
  final bool fixedSegmentsChanged;
  final bool releaseRequested;

  bool get hasEnoughPoints => incomingPoints.length >= 2;
}

final class _ElbowEditPipeline {
  _ElbowEditPipeline({
    required this.element,
    required this.data,
    required this.elementsById,
    this.localPointsOverride,
    this.fixedSegmentsOverride,
    this.startBindingOverride,
    this.endBindingOverride,
  });

  final ElementState element;
  final ArrowData data;
  final Map<String, ElementState> elementsById;
  final List<DrawPoint>? localPointsOverride;
  final List<ElbowFixedSegment>? fixedSegmentsOverride;
  final ArrowBinding? startBindingOverride;
  final ArrowBinding? endBindingOverride;

  ElbowEditResult run() {
    final inputs = _resolveInputs();
    if (!inputs.hasEnoughPoints) {
      return _buildResult(
        data: inputs.data,
        points: inputs.incomingPoints,
        fixedSegments: null,
      );
    }

    if (inputs.fixedSegments.isEmpty) {
      return _routeWithoutFixedSegments(inputs);
    }

    if (inputs.releaseRequested) {
      return _handleFixedSegmentReleaseFlow(inputs);
    }

    if (inputs.pointsChanged && !inputs.fixedSegmentsChanged) {
      return _handleEndpointDragFlow(inputs);
    }

    return _applyFixedSegmentsFlow(inputs);
  }

  _ElbowEditInputs _resolveInputs() {
    // Step 1: resolve the base local points from the element and incoming edits.
    final basePoints = _resolveLocalPoints(element, data);
    final incomingPoints = localPointsOverride ?? basePoints;

    // Step 2: sanitize fixed segments and resolve binding overrides.
    final previousFixedSegments = _sanitizeFixedSegments(
      data.fixedSegments,
      basePoints.length,
    );
    final fixedSegments = _sanitizeFixedSegments(
      fixedSegmentsOverride ?? data.fixedSegments,
      incomingPoints.length,
    );
    final startBinding = startBindingOverride ?? data.startBinding;
    final endBinding = endBindingOverride ?? data.endBinding;

    final pointsChanged = !_pointsEqual(basePoints, incomingPoints);
    final fixedSegmentsChanged =
        !_fixedSegmentsEqual(previousFixedSegments, fixedSegments);
    final releaseRequested =
        fixedSegmentsOverride != null &&
        fixedSegments.length < previousFixedSegments.length;

    return _ElbowEditInputs(
      element: element,
      data: data,
      elementsById: elementsById,
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      previousFixedSegments: previousFixedSegments,
      fixedSegments: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
      pointsChanged: pointsChanged,
      fixedSegmentsChanged: fixedSegmentsChanged,
      releaseRequested: releaseRequested,
    );
  }

  ElbowEditResult _routeWithoutFixedSegments(_ElbowEditInputs inputs) {
    // Step 3: no fixed segments means a fresh route is required.
    final routed = routeElbowArrowForElement(
      element: inputs.element,
      data: inputs.data.copyWith(
        startBinding: inputs.startBinding,
        endBinding: inputs.endBinding,
      ),
      elementsById: inputs.elementsById,
      startOverride: inputs.incomingPoints.first,
      endOverride: inputs.incomingPoints.last,
    );
    return _buildResult(
      data: inputs.data,
      points: routed.localPoints,
      fixedSegments: null,
    );
  }

  ElbowEditResult _handleFixedSegmentReleaseFlow(_ElbowEditInputs inputs) {
    // Step 4: fixed segment release (e.g. user unpins a segment).
    final updated = _handleFixedSegmentRelease(
      element: inputs.element,
      data: inputs.data,
      elementsById: inputs.elementsById,
      currentPoints: inputs.incomingPoints,
      previousFixed: inputs.previousFixedSegments,
      remainingFixed: inputs.fixedSegments,
      startBinding: inputs.startBinding,
      endBinding: inputs.endBinding,
    );
    final mapped = _applyFixedSegmentsToBaselineRoute(
      baseline: updated.points,
      fixedSegments: updated.fixedSegments,
    );
    final reconciled = mapped.fixedSegments.length == updated.fixedSegments.length
        ? mapped
        : updated;
    final normalized = _normalizeFixedSegmentReleasePath(
      points: reconciled.points,
      fixedSegments: reconciled.fixedSegments,
    );
    final resultSegments = normalized.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(normalized.fixedSegments);
    return _buildResult(
      data: inputs.data,
      points: normalized.points,
      fixedSegments: resultSegments,
    );
  }

  ElbowEditResult _handleEndpointDragFlow(_ElbowEditInputs inputs) {
    // Step 5: endpoint drag while fixed segments stay pinned.
    final updated = _applyEndpointDragWithFixedSegments(
      context: _EndpointDragContext(
        element: inputs.element,
        elementsById: inputs.elementsById,
        basePoints: inputs.basePoints,
        incomingPoints: inputs.incomingPoints,
        fixedSegments: inputs.fixedSegments,
        startBinding: inputs.startBinding,
        endBinding: inputs.endBinding,
        startArrowhead: inputs.data.startArrowhead,
        endArrowhead: inputs.data.endArrowhead,
      ),
    );
    final resultSegments = updated.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(updated.fixedSegments);
    return _buildResult(
      data: inputs.data,
      points: List<DrawPoint>.unmodifiable(updated.points),
      fixedSegments: resultSegments,
    );
  }

  ElbowEditResult _applyFixedSegmentsFlow(_ElbowEditInputs inputs) {
    // Step 6: apply fixed segments to updated points if needed.
    var workingPoints = inputs.incomingPoints;
    if (!inputs.pointsChanged && inputs.fixedSegmentsChanged) {
      workingPoints = _applyFixedSegmentsToPoints(
        inputs.basePoints,
        inputs.fixedSegments,
      );
    }
    workingPoints = _applyFixedSegmentsToPoints(
      workingPoints,
      inputs.fixedSegments,
    );

    // Step 7: simplify and reindex segments to keep the path stable.
    final simplified = _simplifyFixedSegmentPath(
      points: workingPoints,
      fixedSegments: inputs.fixedSegments,
    );
    final resultSegments = simplified.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(simplified.fixedSegments);

    return _buildResult(
      data: inputs.data,
      points: simplified.points,
      fixedSegments: resultSegments,
    );
  }
}

ElbowEditResult _buildResult({
  required ArrowData data,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment>? fixedSegments,
}) => ElbowEditResult(
  localPoints: points,
  fixedSegments: fixedSegments,
  startIsSpecial: data.startIsSpecial,
  endIsSpecial: data.endIsSpecial,
);

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) {
  // Route the edit through a step-based pipeline for clarity.
  return _ElbowEditPipeline(
    element: element,
    data: data,
    elementsById: elementsById,
    localPointsOverride: localPointsOverride,
    fixedSegmentsOverride: fixedSegmentsOverride,
    startBindingOverride: startBindingOverride,
    endBindingOverride: endBindingOverride,
  ).run();
}

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
