import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

enum ArrowPointKind { turning, addable, loopStart, loopEnd }

@immutable
class ArrowPointHandle {
  const ArrowPointHandle({
    required this.elementId,
    required this.kind,
    required this.index,
    required this.position,
  });

  /// Element id that owns this control point.
  final String elementId;

  /// Control point kind.
  final ArrowPointKind kind;

  /// Turning point index (or segment start index for addable points).
  final int index;

  /// World-space position in the element's un-rotated coordinate space.
  final DrawPoint position;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowPointHandle &&
          other.elementId == elementId &&
          other.kind == kind &&
          other.index == index;

  @override
  int get hashCode => Object.hash(elementId, kind, index);

  @override
  String toString() =>
      'ArrowPointHandle(id: $elementId, kind: $kind, index: $index)';
}

@immutable
class ArrowPointOverlay {
  const ArrowPointOverlay({
    required this.turningPoints,
    required this.addablePoints,
    required this.loopPoints,
  });

  final List<ArrowPointHandle> turningPoints;
  final List<ArrowPointHandle> addablePoints;
  final List<ArrowPointHandle> loopPoints;

  bool get hasLoop => loopPoints.isNotEmpty;
}

class ArrowPointUtils {
  const ArrowPointUtils._();

  static ArrowPointOverlay buildOverlay({
    required ElementState element,
    required double loopThreshold,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      return const ArrowPointOverlay(
        turningPoints: [],
        addablePoints: [],
        loopPoints: [],
      );
    }

    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      return const ArrowPointOverlay(
        turningPoints: [],
        addablePoints: [],
        loopPoints: [],
      );
    }

    final loopActive =
        points.first.distanceSquared(points.last) <= loopThreshold * loopThreshold;

    final turningPoints = <ArrowPointHandle>[];
    for (var i = 0; i < points.length; i++) {
      if (loopActive && (i == 0 || i == points.length - 1)) {
        continue;
      }
      turningPoints.add(
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.turning,
          index: i,
          position: points[i],
        ),
      );
    }

    final addablePoints = <ArrowPointHandle>[];
    for (var i = 0; i < points.length - 1; i++) {
      final mid = _midpoint(points[i], points[i + 1]);
      addablePoints.add(
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.addable,
          index: i,
          position: mid,
        ),
      );
    }

    final loopPoints = <ArrowPointHandle>[];
    if (loopActive) {
      loopPoints.add(
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopStart,
          index: 0,
          position: points.first,
        ),
      );
      loopPoints.add(
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopEnd,
          index: points.length - 1,
          position: points.last,
        ),
      );
    }

    return ArrowPointOverlay(
      turningPoints: List<ArrowPointHandle>.unmodifiable(turningPoints),
      addablePoints: List<ArrowPointHandle>.unmodifiable(addablePoints),
      loopPoints: List<ArrowPointHandle>.unmodifiable(loopPoints),
    );
  }

  static ArrowPointHandle? hitTest({
    required ElementState element,
    required DrawPoint position,
    required double hitRadius,
    required double loopThreshold,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      return null;
    }
    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      return null;
    }

    final localPosition = _toLocalPosition(element, position);
    final loopActive =
        points.first.distanceSquared(points.last) <= loopThreshold * loopThreshold;

    if (loopActive) {
      final distanceSq = localPosition.distanceSquared(points.first);
      final outerRadiusSq = hitRadius * hitRadius;
      final innerRadius = hitRadius * 0.6;
      final innerRadiusSq = innerRadius * innerRadius;
      if (distanceSq <= innerRadiusSq) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopStart,
          index: 0,
          position: points.first,
        );
      }
      if (distanceSq <= outerRadiusSq) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopEnd,
          index: points.length - 1,
          position: points.last,
        );
      }
    }

    ArrowPointHandle? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      if (loopActive && (i == 0 || i == points.length - 1)) {
        continue;
      }
      final distanceSq = localPosition.distanceSquared(points[i]);
      if (distanceSq <= hitRadius * hitRadius &&
          distanceSq < nearestDistance) {
        nearestDistance = distanceSq;
        nearest = ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.turning,
          index: i,
          position: points[i],
        );
      }
    }
    if (nearest != null) {
      return nearest;
    }

    for (var i = 0; i < points.length - 1; i++) {
      final mid = _midpoint(points[i], points[i + 1]);
      final distanceSq = localPosition.distanceSquared(mid);
      if (distanceSq <= hitRadius * hitRadius) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.addable,
          index: i,
          position: mid,
        );
      }
    }

    return null;
  }

  static List<DrawPoint> _resolveWorldPoints(
    ElementState element,
    ArrowData data,
  ) {
    final resolved = ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
    return resolved
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
  }

  static DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  static DrawPoint _midpoint(DrawPoint a, DrawPoint b) =>
      DrawPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);
}
