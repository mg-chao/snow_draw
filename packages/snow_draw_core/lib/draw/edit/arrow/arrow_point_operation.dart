import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_style.dart';
import '../apply/edit_apply.dart';
import '../core/edit_errors.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../preview/edit_preview.dart';

class ArrowPointOperation extends EditOperation {
  const ArrowPointOperation();

  @override
  EditOperationId get id => EditOperationIds.arrowPoint;

  @override
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.createHistoryMetadata',
    );
    return HistoryMetadata.forEdit(
      operationType: 'Arrow point',
      elementIds: typedContext.selectedIdsAtStart,
    );
  }

  @override
  ArrowPointEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<ArrowPointOperationParams>(
      params,
      operationName: 'ArrowPointOperation.createContext',
    );
    final element = state.domain.document.getElementById(typedParams.elementId);
    if (element == null || element.data is! ArrowData) {
      throw const EditMissingDataError(
        dataName: 'arrow element',
        operationName: 'ArrowPointOperation.createContext',
      );
    }
    final data = element.data as ArrowData;
    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      throw const EditMissingDataError(
        dataName: 'arrow points',
        operationName: 'ArrowPointOperation.createContext',
      );
    }

    final startBounds = requireSelectionBounds(
      selectionData: SelectionDataComputer.compute(state),
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'ArrowPointOperation.createContext',
    );

    final localStartPosition = _toLocalPosition(
      element.rect,
      element.rotation,
      position,
    );
    final pointPosition = _resolvePointPosition(
      points: points,
      kind: typedParams.pointKind,
      index: typedParams.pointIndex,
      arrowType: data.arrowType,
    );
    final dragOffset = pointPosition - localStartPosition;
    final selectedIdsAtStart = {...state.domain.selection.selectedIds};

    return ArrowPointEditContext(
      startPosition: localStartPosition,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
      elementId: element.id,
      elementRect: element.rect,
      rotation: element.rotation,
      initialPoints: List<DrawPoint>.unmodifiable(points),
      arrowType: data.arrowType,
      pointKind: typedParams.pointKind,
      pointIndex: typedParams.pointIndex,
      dragOffset: dragOffset,
    );
  }

  @override
  ArrowPointTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.initialTransform',
    );
    return ArrowPointTransform(
      currentPosition: startPosition,
      points: typedContext.initialPoints,
    );
  }

  @override
  EditUpdateResult<EditTransform> update({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
    required DrawConfig config,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.update',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.update',
    );

    final localPosition = _toLocalPosition(
      typedContext.elementRect,
      typedContext.rotation,
      currentPosition,
    );
    final zoom = state.application.view.camera.zoom;
    final result = _compute(
      context: typedContext,
      currentPosition: localPosition,
      didInsert: typedTransform.didInsert,
      config: config,
      zoom: zoom,
    );

    final nextTransform = typedTransform.copyWith(
      currentPosition: localPosition,
      points: result.points,
      activeIndex: result.activeIndex,
      didInsert: result.didInsert,
      shouldDelete: result.shouldDelete,
      hasChanges: result.hasChanges,
    );

    return EditUpdateResult<EditTransform>(transform: nextTransform);
  }

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.finish',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.finish',
    );
    if (!typedTransform.hasChanges) {
      return state.copyWith(application: state.application.toIdle());
    }

    final points = List<DrawPoint>.from(typedTransform.points);
    if (typedTransform.shouldDelete &&
        typedTransform.activeIndex != null &&
        typedTransform.activeIndex! > 0 &&
        typedTransform.activeIndex! < points.length - 1) {
      points.removeAt(typedTransform.activeIndex!);
    }

    if (points.length < 2) {
      return state.copyWith(application: state.application.toIdle());
    }

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    if (element == null || element.data is! ArrowData) {
      return state.copyWith(application: state.application.toIdle());
    }

    final data = element.data as ArrowData;

    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = _computeRectAndPoints(
      localPoints: points,
      oldRect: typedContext.elementRect,
      rotation: typedContext.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );

    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );

    final updatedData = data.copyWith(points: normalized);
    final updatedElement = element.copyWith(
      rect: result.rect,
      data: updatedData,
    );
    final updatedElements = EditApply.replaceElementsById(
      elements: state.domain.document.elements,
      replacementsById: {updatedElement.id: updatedElement},
    );

    return state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(elements: updatedElements),
      ),
      application: state.application.copyWith(interaction: const IdleState()),
    );
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.buildPreview',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.buildPreview',
    );
    if (!typedTransform.hasChanges) {
      return EditPreview.none;
    }

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    if (element == null || element.data is! ArrowData) {
      return EditPreview.none;
    }

    final data = element.data as ArrowData;

    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = _computeRectAndPoints(
      localPoints: typedTransform.points,
      oldRect: typedContext.elementRect,
      rotation: typedContext.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );

    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );

    final updatedData = data.copyWith(points: normalized);
    final updatedElement = element.copyWith(
      rect: result.rect,
      data: updatedData,
    );

    return buildEditPreview(
      state: state,
      context: typedContext,
      previewElementsById: {updatedElement.id: updatedElement},
    );
  }
}

@immutable
final class ArrowPointEditContext extends EditContext {
  const ArrowPointEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.elementId,
    required this.elementRect,
    required this.rotation,
    required this.initialPoints,
    required this.arrowType,
    required this.pointKind,
    required this.pointIndex,
    required this.dragOffset,
  });

  final String elementId;
  final DrawRect elementRect;
  final double rotation;
  final List<DrawPoint> initialPoints;
  final ArrowType arrowType;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final DrawPoint dragOffset;
}

@immutable
final class _ArrowPointComputation {
  const _ArrowPointComputation({
    required this.points,
    required this.didInsert,
    required this.shouldDelete,
    required this.activeIndex,
    required this.hasChanges,
  });

  final List<DrawPoint> points;
  final bool didInsert;
  final bool shouldDelete;
  final int? activeIndex;
  final bool hasChanges;
}

_ArrowPointComputation _compute({
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required DrawConfig config,
  required double zoom,
}) {
  final basePoints = List<DrawPoint>.from(context.initialPoints);
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  final handleTolerance =
      config.selection.interaction.handleTolerance / effectiveZoom;
  final addThreshold = handleTolerance;
  final deleteThreshold = handleTolerance;
  final loopThreshold = handleTolerance * 1.5;
  final isPolyline = context.arrowType == ArrowType.polyline;

  final target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  int? activeIndex;

  if (context.pointKind == ArrowPointKind.addable) {
    if (context.pointIndex < 0 || context.pointIndex >= basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: false,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
      );
    }
    if (isPolyline) {
      if (!nextDidInsert) {
        final distanceSq = currentPosition.distanceSquared(
          context.startPosition,
        );
        if (distanceSq >= addThreshold * addThreshold) {
          nextDidInsert = true;
        } else {
          return _ArrowPointComputation(
            points: basePoints,
            didInsert: false,
            shouldDelete: false,
            activeIndex: null,
            hasChanges: false,
          );
        }
      }
      updatedPoints = _movePolylineSegment(
        points: basePoints,
        segmentIndex: context.pointIndex,
        target: target,
      );
      updatedPoints = _simplifyPolylinePoints(updatedPoints);
      activeIndex = _resolveNearestSegmentIndex(
        points: updatedPoints,
        target: target,
      );
    } else {
      if (!nextDidInsert) {
        final distanceSq = currentPosition.distanceSquared(
          context.startPosition,
        );
        if (distanceSq >= addThreshold * addThreshold) {
          nextDidInsert = true;
        } else {
          return _ArrowPointComputation(
            points: basePoints,
            didInsert: false,
            shouldDelete: false,
            activeIndex: null,
            hasChanges: false,
          );
        }
      }
      activeIndex = context.pointIndex + 1;
      updatedPoints = List<DrawPoint>.from(basePoints)
        ..insert(activeIndex, target);
    }
  } else {
    final index = switch (context.pointKind) {
      ArrowPointKind.loopStart => 0,
      ArrowPointKind.loopEnd => basePoints.length - 1,
      _ => context.pointIndex,
    };
    if (index < 0 || index >= basePoints.length) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: nextDidInsert,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
      );
    }
    if (isPolyline && index != 0 && index != basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: nextDidInsert,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
      );
    }
    if (isPolyline) {
      updatedPoints = _movePolylineEndpoint(
        points: basePoints,
        index: index,
        target: target,
      );
      updatedPoints = _simplifyPolylinePoints(updatedPoints);
    } else {
      updatedPoints = List<DrawPoint>.from(basePoints);
      updatedPoints[index] = target;
    }
    activeIndex = index;
  }

  if (context.pointKind != ArrowPointKind.addable &&
      (activeIndex == 0 || activeIndex == updatedPoints.length - 1)) {
    final start = updatedPoints.first;
    final end = updatedPoints.last;
    if (start.distanceSquared(end) <= loopThreshold * loopThreshold) {
      if (activeIndex == 0) {
        updatedPoints[0] = end;
      } else {
        updatedPoints[updatedPoints.length - 1] = start;
      }
    }
  }

  var shouldDelete = false;
  if (!isPolyline) {
    final resolvedIndex = activeIndex;
    if (resolvedIndex != null &&
        resolvedIndex > 0 &&
        resolvedIndex < updatedPoints.length - 1) {
      final targetPoint = updatedPoints[resolvedIndex];
      final prev = updatedPoints[resolvedIndex - 1];
      final next = updatedPoints[resolvedIndex + 1];
      if (targetPoint.distanceSquared(prev) <=
              deleteThreshold * deleteThreshold ||
          targetPoint.distanceSquared(next) <=
              deleteThreshold * deleteThreshold) {
        shouldDelete = true;
      }
    }
  }

  final hasChanges = !_pointsEqual(basePoints, updatedPoints) || nextDidInsert;

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    didInsert: nextDidInsert,
    shouldDelete: shouldDelete,
    activeIndex: activeIndex,
    hasChanges: hasChanges,
  );
}

/// Calculates accurate bounding rect for arrow, accounting for curved paths.
DrawRect _calculateArrowRect({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required double strokeWidth,
}) => ArrowGeometry.calculatePathBounds(
  worldPoints: points,
  arrowType: arrowType,
);

/// Result of computing the new rect and adjusted local points.
@immutable
final class _RectAndPointsResult {
  const _RectAndPointsResult({required this.rect, required this.localPoints});

  final DrawRect rect;
  final List<DrawPoint> localPoints;
}

/// Computes the new rect and transforms points to preserve world-space
///  positions.
///
/// When a control point is dragged outside the current bounding rect, the rect
/// must be recalculated. If the element is rotated, simply recalculating the
/// rect
/// would change the rotation pivot (rect center), causing other points to shift
/// in world space.
///
/// This function finds the optimal rect center C such that when world points
/// are
/// transformed to local space using C, the bounding box of local points has
/// center C. This ensures all points maintain their world-space positions.
///
/// The mathematical solution is: C = rotate(W'_center, θ)
/// Where W'_center is the center of the bounding box of world points rotated
/// by -θ around the origin.
_RectAndPointsResult _computeRectAndPoints({
  required List<DrawPoint> localPoints,
  required DrawRect oldRect,
  required double rotation,
  required ArrowType arrowType,
  required double strokeWidth,
}) {
  // For non-rotated elements, no transformation needed
  if (rotation == 0) {
    final rect = _calculateArrowRect(
      points: localPoints,
      arrowType: arrowType,
      strokeWidth: strokeWidth,
    );
    return _RectAndPointsResult(rect: rect, localPoints: localPoints);
  }

  // Step 1: Transform local-space points to world space using the old rect
  // center
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final worldPoints = localPoints.map(oldSpace.toWorld).toList(growable: false);

  // Step 2: Rotate world points by -θ around the origin
  final cosTheta = math.cos(rotation);
  final sinTheta = math.sin(rotation);
  final rotatedPoints = worldPoints
      .map(
        (w) => DrawPoint(
          x: w.x * cosTheta + w.y * sinTheta,
          y: -w.x * sinTheta + w.y * cosTheta,
        ),
      )
      .toList(growable: false);

  // Step 3: Calculate the bounding box of rotated points
  var minX = rotatedPoints.first.x;
  var maxX = rotatedPoints.first.x;
  var minY = rotatedPoints.first.y;
  var maxY = rotatedPoints.first.y;
  for (final p in rotatedPoints.skip(1)) {
    if (p.x < minX) {
      minX = p.x;
    }
    if (p.x > maxX) {
      maxX = p.x;
    }
    if (p.y < minY) {
      minY = p.y;
    }
    if (p.y > maxY) {
      maxY = p.y;
    }
  }
  final rotatedCenterX = (minX + maxX) / 2;
  final rotatedCenterY = (minY + maxY) / 2;

  // Step 4: The new rect center is the rotated center rotated back by θ
  // C = rotate(W'_center, θ)
  final newCenterX = rotatedCenterX * cosTheta - rotatedCenterY * sinTheta;
  final newCenterY = rotatedCenterX * sinTheta + rotatedCenterY * cosTheta;
  final newCenter = DrawPoint(x: newCenterX, y: newCenterY);

  // Step 5: Transform world points to local space using the new center
  final newSpace = ElementSpace(rotation: rotation, origin: newCenter);
  final newLocalPoints = worldPoints
      .map(newSpace.fromWorld)
      .toList(growable: false);

  // Step 6: Calculate the rect from local points
  // The bounding box center should now equal newCenter
  final rect = _calculateArrowRect(
    points: newLocalPoints,
    arrowType: arrowType,
    strokeWidth: strokeWidth,
  );

  return _RectAndPointsResult(rect: rect, localPoints: newLocalPoints);
}

List<DrawPoint> _resolveWorldPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  final effective = data.arrowType == ArrowType.polyline
      ? ArrowGeometry.expandPolylinePoints(resolved)
      : resolved;
  return effective
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

DrawPoint _resolvePointPosition({
  required List<DrawPoint> points,
  required ArrowPointKind kind,
  required int index,
  required ArrowType arrowType,
}) {
  if (kind == ArrowPointKind.addable) {
    if (index < 0 || index >= points.length - 1) {
      return points.first;
    }

    // For curved arrows with 3+ points, calculate point on the actual curve
    if (arrowType == ArrowType.curved && points.length >= 3) {
      final offsetPoints = points
          .map((p) => Offset(p.x, p.y))
          .toList(growable: false);
      final curvePoint = ArrowGeometry.calculateCurvePoint(
        points: offsetPoints,
        segmentIndex: index,
        t: 0.5,
      );
      if (curvePoint != null) {
        return DrawPoint(x: curvePoint.dx, y: curvePoint.dy);
      }
    }

    // For straight and polyline arrows, use linear midpoint
    final start = points[index];
    final end = points[index + 1];
    return DrawPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2);
  }
  final resolvedIndex = switch (kind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => points.length - 1,
    _ => index,
  };
  return points[resolvedIndex.clamp(0, points.length - 1)];
}

DrawPoint _toLocalPosition(DrawRect rect, double rotation, DrawPoint position) {
  if (rotation == 0) {
    return position;
  }
  final space = ElementSpace(rotation: rotation, origin: rect.center);
  return space.fromWorld(position);
}

bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

List<DrawPoint> _movePolylineSegment({
  required List<DrawPoint> points,
  required int segmentIndex,
  required DrawPoint target,
}) {
  if (segmentIndex < 0 || segmentIndex >= points.length - 1) {
    return points;
  }
  if (segmentIndex == 0 || segmentIndex == points.length - 2) {
    return _offsetPolylineEndpointSegment(
      points: points,
      segmentIndex: segmentIndex,
      target: target,
    );
  }
  final start = points[segmentIndex];
  final end = points[segmentIndex + 1];
  final isHorizontal = _segmentIsHorizontal(start, end);
  final updated = List<DrawPoint>.from(points);
  if (isHorizontal) {
    updated[segmentIndex] = DrawPoint(x: start.x, y: target.y);
    updated[segmentIndex + 1] = DrawPoint(x: end.x, y: target.y);
  } else {
    updated[segmentIndex] = DrawPoint(x: target.x, y: start.y);
    updated[segmentIndex + 1] = DrawPoint(x: target.x, y: end.y);
  }
  return updated;
}

List<DrawPoint> _offsetPolylineEndpointSegment({
  required List<DrawPoint> points,
  required int segmentIndex,
  required DrawPoint target,
}) {
  if (points.length < 2 ||
      segmentIndex < 0 ||
      segmentIndex >= points.length - 1) {
    return points;
  }
  final start = points[segmentIndex];
  final end = points[segmentIndex + 1];
  if (points.length == 2) {
    return [start, target, end];
  }
  final isHorizontal = _segmentIsHorizontal(start, end);
  final movedStart = isHorizontal
      ? DrawPoint(x: start.x, y: target.y)
      : DrawPoint(x: target.x, y: start.y);
  final movedEnd = isHorizontal
      ? DrawPoint(x: end.x, y: target.y)
      : DrawPoint(x: target.x, y: end.y);
  if (segmentIndex == 0) {
    return [start, movedStart, movedEnd, ...points.sublist(2)];
  }
  return [...points.sublist(0, points.length - 2), movedStart, movedEnd, end];
}

int? _resolveNearestSegmentIndex({
  required List<DrawPoint> points,
  required DrawPoint target,
}) {
  if (points.length < 2) {
    return null;
  }
  var nearestIndex = 0;
  var nearestDistance = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final mid = DrawPoint(
      x: (points[i].x + points[i + 1].x) / 2,
      y: (points[i].y + points[i + 1].y) / 2,
    );
    final distance = target.distanceSquared(mid);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = i;
    }
  }
  return nearestIndex;
}

List<DrawPoint> _movePolylineEndpoint({
  required List<DrawPoint> points,
  required int index,
  required DrawPoint target,
}) {
  final updated = List<DrawPoint>.from(points);
  if (index < 0 || index >= updated.length) {
    return updated;
  }
  updated[index] = target;
  if (updated.length < 3) {
    return updated;
  }
  if (index == 0) {
    final next = updated[1];
    final wasHorizontal = _segmentIsHorizontal(points[0], points[1]);
    updated[1] = DrawPoint(
      x: wasHorizontal ? next.x : target.x,
      y: wasHorizontal ? target.y : next.y,
    );
  } else if (index == updated.length - 1) {
    final prev = updated[updated.length - 2];
    final wasHorizontal = _segmentIsHorizontal(
      points[points.length - 2],
      points[points.length - 1],
    );
    updated[updated.length - 2] = DrawPoint(
      x: wasHorizontal ? prev.x : target.x,
      y: wasHorizontal ? target.y : prev.y,
    );
  }
  return updated;
}

List<DrawPoint> _simplifyPolylinePoints(List<DrawPoint> points) {
  if (points.length < 3) {
    return points;
  }
  final simplified = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final prev = simplified.last;
    final current = points[i];
    final next = points[i + 1];

    if (_isSamePoint(prev, current)) {
      continue;
    }

    if (_isCollinear(prev, current, next) &&
        _isSameDirection(prev, current, next)) {
      continue;
    }
    simplified.add(current);
  }
  final last = points.last;
  if (simplified.isEmpty || !_isSamePoint(simplified.last, last)) {
    simplified.add(last);
  }
  return simplified.length < 2 ? points : simplified;
}

bool _nearZero(double value) => value.abs() <= 1.0;

bool _isSamePoint(DrawPoint a, DrawPoint b) =>
    _nearZero(a.x - b.x) && _nearZero(a.y - b.y);

bool _isCollinear(DrawPoint a, DrawPoint b, DrawPoint c) {
  const tolerance = 1.0;
  final acx = c.x - a.x;
  final acy = c.y - a.y;
  final lengthSq = acx * acx + acy * acy;
  if (lengthSq <= tolerance * tolerance) {
    return true;
  }
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final cross = abx * acy - aby * acx;
  return cross * cross <= tolerance * tolerance * lengthSq;
}

bool _isSameDirection(DrawPoint a, DrawPoint b, DrawPoint c) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final bcx = c.x - b.x;
  final bcy = c.y - b.y;
  return (abx * bcx + aby * bcy) >= 0;
}

bool _segmentIsHorizontal(DrawPoint start, DrawPoint end) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  if (_nearZero(dy) && !_nearZero(dx)) {
    return true;
  }
  if (_nearZero(dx) && !_nearZero(dy)) {
    return false;
  }
  return dx.abs() > dy.abs();
}
