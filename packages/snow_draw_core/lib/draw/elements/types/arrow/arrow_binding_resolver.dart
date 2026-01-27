import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_binding.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';
import 'arrow_layout.dart';

@immutable
final class ArrowBindingResolver {
  const ArrowBindingResolver._();

  static Map<String, ElementState> resolveBoundArrows({
    required Map<String, ElementState> elementsById,
    required Set<String> changedElementIds,
  }) {
    if (changedElementIds.isEmpty) {
      return const {};
    }

    final updates = <String, ElementState>{};
    for (final element in elementsById.values) {
      final data = element.data;
      if (data is! ArrowData) {
        continue;
      }
      final startBinding = data.startBinding;
      final endBinding = data.endBinding;
      if (startBinding == null && endBinding == null) {
        continue;
      }

      final updateStart =
          startBinding != null &&
          changedElementIds.contains(startBinding.elementId);
      final updateEnd =
          endBinding != null &&
          changedElementIds.contains(endBinding.elementId);
      if (!updateStart && !updateEnd) {
        continue;
      }

      final updated = _applyBindings(
        element: element,
        data: data,
        elementsById: elementsById,
        updateStart: updateStart,
        updateEnd: updateEnd,
      );
      if (updated != null) {
        updates[updated.id] = updated;
      }
    }

    return updates;
  }
}

ElementState? _applyBindings({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  required bool updateStart,
  required bool updateEnd,
}) {
  final localPoints = _resolveLocalPoints(element, data);
  if (localPoints.length < 2) {
    return null;
  }
  final originalPoints = List<DrawPoint>.from(localPoints);

  final rect = element.rect;
  final space = ElementSpace(rotation: element.rotation, origin: rect.center);
  final startReference = localPoints.length > 1
      ? space.toWorld(localPoints[1])
      : null;
  final endReference = localPoints.length > 1
      ? space.toWorld(localPoints[localPoints.length - 2])
      : null;

  var startUpdated = false;
  var endUpdated = false;

  if (updateStart && data.startBinding != null) {
    final target = elementsById[data.startBinding!.elementId];
    final bound = target == null
        ? null
        : ArrowBindingUtils.resolveBoundPoint(
            binding: data.startBinding!,
            target: target,
            referencePoint: startReference,
          );
    if (bound != null) {
      localPoints[0] = space.fromWorld(bound);
      startUpdated = true;
    }
  }

  if (updateEnd && data.endBinding != null) {
    final target = elementsById[data.endBinding!.elementId];
    final bound = target == null
        ? null
        : ArrowBindingUtils.resolveBoundPoint(
            binding: data.endBinding!,
            target: target,
            referencePoint: endReference,
          );
    if (bound != null) {
      localPoints[localPoints.length - 1] = space.fromWorld(bound);
      endUpdated = true;
    }
  }

  if (!startUpdated && !endUpdated) {
    return null;
  }

  var adjustedPoints = localPoints;
  if (data.arrowType == ArrowType.polyline) {
    adjustedPoints = _adjustPolylineEndpoints(
      points: localPoints,
      originalPoints: originalPoints,
      startUpdated: startUpdated,
      endUpdated: endUpdated,
    );
  }

  final result = computeArrowRectAndPoints(
    localPoints: adjustedPoints,
    oldRect: rect,
    rotation: element.rotation,
    arrowType: data.arrowType,
    strokeWidth: data.strokeWidth,
  );

  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: result.localPoints,
    rect: result.rect,
  );

  final updatedData = data.copyWith(points: normalized);
  if (updatedData == data && result.rect == rect) {
    return null;
  }

  return element.copyWith(rect: result.rect, data: updatedData);
}

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
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

List<DrawPoint> _adjustPolylineEndpoints({
  required List<DrawPoint> points,
  required List<DrawPoint> originalPoints,
  required bool startUpdated,
  required bool endUpdated,
}) {
  if (points.length < 2) {
    return points;
  }

  final updated = List<DrawPoint>.from(points);

  if (startUpdated && originalPoints.length >= 2) {
    final wasHorizontal = ArrowGeometry.isPolylineSegmentHorizontal(
      originalPoints[0],
      originalPoints[1],
    );
    final anchor = updated[0];
    final neighbor = updated[1];
    updated[1] = wasHorizontal
        ? DrawPoint(x: neighbor.x, y: anchor.y)
        : DrawPoint(x: anchor.x, y: neighbor.y);
  }

  if (endUpdated && originalPoints.length >= 2) {
    final lastIndex = updated.length - 1;
    final prevIndex = lastIndex - 1;
    final wasHorizontal = ArrowGeometry.isPolylineSegmentHorizontal(
      originalPoints[prevIndex],
      originalPoints[lastIndex],
    );
    final anchor = updated[lastIndex];
    final neighbor = updated[prevIndex];
    updated[prevIndex] = wasHorizontal
        ? DrawPoint(x: neighbor.x, y: anchor.y)
        : DrawPoint(x: anchor.x, y: neighbor.y);
  }

  return updated;
}
