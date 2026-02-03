import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
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
    this.isFixed = false,
  });

  /// Element id that owns this control point.
  final String elementId;

  /// Control point kind.
  final ArrowPointKind kind;

  /// Turning point index (or segment start index for addable points).
  final int index;

  /// World-space position in the element's un-rotated coordinate space.
  final DrawPoint position;

  /// Whether the handle represents a fixed elbow segment.
  final bool isFixed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowPointHandle &&
          other.elementId == elementId &&
          other.kind == kind &&
          other.index == index &&
          other.isFixed == isFixed;

  @override
  int get hashCode => Object.hash(elementId, kind, index, isFixed);

  @override
  String toString() =>
      'ArrowPointHandle(id: $elementId, kind: $kind, index: $index, '
      'isFixed: $isFixed)';
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
    double? handleSize,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      return const ArrowPointOverlay(
        turningPoints: [],
        addablePoints: [],
        loopPoints: [],
      );
    }

    final rawPoints = _resolveWorldPoints(element, data);
    if (rawPoints.length < 2) {
      return const ArrowPointOverlay(
        turningPoints: [],
        addablePoints: [],
        loopPoints: [],
      );
    }

    if (data.arrowType == ArrowType.elbow) {
      final turningPoints = <ArrowPointHandle>[
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.turning,
          index: 0,
          position: rawPoints.first,
        ),
      ];
      if (rawPoints.length > 1) {
        turningPoints.add(
          ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.turning,
            index: rawPoints.length - 1,
            position: rawPoints.last,
          ),
        );
      }
      final addablePoints = <ArrowPointHandle>[];
      final fixedSegments = data.fixedSegments ?? const [];
      for (var i = 0; i < rawPoints.length - 1; i++) {
        if (_isSegmentTooShort(rawPoints[i], rawPoints[i + 1], handleSize)) {
          continue;
        }
        final segmentIndex = i + 1;
        final isFixed = fixedSegments.any(
          (segment) => segment.index == segmentIndex,
        );
        addablePoints.add(
          ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.addable,
            index: i,
            position: _midpoint(rawPoints[i], rawPoints[i + 1]),
            isFixed: isFixed,
          ),
        );
      }
      return ArrowPointOverlay(
        turningPoints: List<ArrowPointHandle>.unmodifiable(turningPoints),
        addablePoints: List<ArrowPointHandle>.unmodifiable(addablePoints),
        loopPoints: const [],
      );
    }

    final segmentPoints = _resolveSegmentPoints(rawPoints);

    final loopActive =
        rawPoints.first.distanceSquared(rawPoints.last) <=
        loopThreshold * loopThreshold;

    final turningPoints = <ArrowPointHandle>[];
    for (var i = 0; i < rawPoints.length; i++) {
      if (loopActive && (i == 0 || i == rawPoints.length - 1)) {
        continue;
      }
      turningPoints.add(
        ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.turning,
          index: i,
          position: rawPoints[i],
        ),
      );
    }

    final addablePoints = <ArrowPointHandle>[];
    for (var i = 0; i < segmentPoints.length - 1; i++) {
      final mid = _calculateMidpoint(segmentPoints, i, data.arrowType);
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
      loopPoints
        ..add(
          ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.loopStart,
            index: 0,
            position: rawPoints.first,
          ),
        )
        ..add(
          ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.loopEnd,
            index: rawPoints.length - 1,
            position: rawPoints.last,
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
    double? handleSize,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      return null;
    }
    final rawPoints = _resolveWorldPoints(element, data);
    if (rawPoints.length < 2) {
      return null;
    }

    final segmentPoints = _resolveSegmentPoints(rawPoints);

    final localPosition = _toLocalPosition(element, position);
    final visualPointRadius = handleSize == null || handleSize <= 0
        ? 0.0
        : handleSize * 0.5;
    final visualLoopOuterRadius = handleSize == null || handleSize <= 0
        ? 0.0
        : handleSize * 1.0;
    final visualLoopInnerRadius = visualPointRadius;
    final loopActive =
        rawPoints.first.distanceSquared(rawPoints.last) <=
        loopThreshold * loopThreshold;

    if (data.arrowType == ArrowType.elbow) {
      ArrowPointHandle? nearest;
      var nearestDistance = double.infinity;
      var turningHitRadius = hitRadius * 1.11;
      if (visualPointRadius > turningHitRadius) {
        turningHitRadius = visualPointRadius;
      }
      final localPoints = [rawPoints.first, rawPoints.last];
      for (var i = 0; i < localPoints.length; i++) {
        final index = i == 0 ? 0 : rawPoints.length - 1;
        final distanceSq = localPosition.distanceSquared(localPoints[i]);
        if (distanceSq <= turningHitRadius * turningHitRadius &&
            distanceSq < nearestDistance) {
          nearestDistance = distanceSq;
          nearest = ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.turning,
            index: index,
            position: localPoints[i],
          );
        }
      }
      if (nearest != null) {
        return nearest;
      }

      final fixedSegments = data.fixedSegments ?? const [];
      final segmentHitRadius = hitRadius;
      for (var i = 0; i < rawPoints.length - 1; i++) {
        if (_isSegmentTooShort(rawPoints[i], rawPoints[i + 1], handleSize)) {
          continue;
        }
        final midpoint = _midpoint(rawPoints[i], rawPoints[i + 1]);
        final distanceSq = localPosition.distanceSquared(midpoint);
        if (distanceSq <= segmentHitRadius * segmentHitRadius) {
          final segmentIndex = i + 1;
          final isFixed = fixedSegments.any(
            (segment) => segment.index == segmentIndex,
          );
          return ArrowPointHandle(
            elementId: element.id,
            kind: ArrowPointKind.addable,
            index: i,
            position: midpoint,
            isFixed: isFixed,
          );
        }
      }
      return null;
    }

    if (loopActive) {
      // Use the midpoint between first and last as the loop center for hit
      // testing
      final loopCenter = _midpoint(rawPoints.first, rawPoints.last);
      final distanceSq = localPosition.distanceSquared(loopCenter);

      // Loop outer radius: 0.65 (was 0.55), scale hit radius proportionally
      var outerRadius = hitRadius * 1.18;
      if (visualLoopOuterRadius > outerRadius) {
        outerRadius = visualLoopOuterRadius;
      }
      final outerRadiusSq = outerRadius * outerRadius;
      // Loop inner radius: 0.40 (was 0.35), scale hit radius proportionally
      var innerRadius = hitRadius * 0.69;
      if (visualLoopInnerRadius > innerRadius) {
        innerRadius = visualLoopInnerRadius;
      }
      final innerRadiusSq = innerRadius * innerRadius;

      // Check inner loop point first (higher priority)
      if (distanceSq <= innerRadiusSq) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopStart,
          index: 0,
          position: rawPoints.first,
        );
      }

      // Check outer loop ring (between inner and outer radius)
      if (distanceSq <= outerRadiusSq) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.loopEnd,
          index: rawPoints.length - 1,
          position: rawPoints.last,
        );
      }
    }

    ArrowPointHandle? nearest;
    var nearestDistance = double.infinity;
    // Turning point radius: 0.50 (was 0.45), scale hit radius proportionally
    var turningHitRadius = hitRadius * 1.11;
    if (visualPointRadius > turningHitRadius) {
      turningHitRadius = visualPointRadius;
    }
    for (var i = 0; i < rawPoints.length; i++) {
      if (loopActive && (i == 0 || i == rawPoints.length - 1)) {
        continue;
      }
      final distanceSq = localPosition.distanceSquared(rawPoints[i]);
      if (distanceSq <= turningHitRadius * turningHitRadius &&
          distanceSq < nearestDistance) {
        nearestDistance = distanceSq;
        nearest = ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.turning,
          index: i,
          position: rawPoints[i],
        );
      }
    }
    if (nearest != null) {
      return nearest;
    }

    // Addable point radius: 0.50 (was 0.35), scale hit radius proportionally
    var addableHitRadius = hitRadius * 1.43;
    if (visualPointRadius > addableHitRadius) {
      addableHitRadius = visualPointRadius;
    }
    for (var i = 0; i < segmentPoints.length - 1; i++) {
      final mid = _calculateMidpoint(segmentPoints, i, data.arrowType);
      final distanceSq = localPosition.distanceSquared(mid);
      if (distanceSq <= addableHitRadius * addableHitRadius) {
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

  static List<DrawPoint> _resolveSegmentPoints(List<DrawPoint> rawPoints) =>
      rawPoints;

  static DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  /// Calculates the midpoint for an addable point between two control points.
  /// For curved arrows, this uses the actual curve position at t=0.5.
  /// For straight arrows, this uses linear interpolation.
  static DrawPoint _calculateMidpoint(
    List<DrawPoint> points,
    int segmentIndex,
    ArrowType arrowType,
  ) {
    if (segmentIndex < 0 || segmentIndex >= points.length - 1) {
      return points.first;
    }

    // For curved arrows with 3+ points, calculate point on the actual curve
    if (arrowType == ArrowType.curved && points.length >= 3) {
      final offsetPoints = points
          .map((p) => Offset(p.x, p.y))
          .toList(growable: false);
      final curvePoint = ArrowGeometry.calculateCurvePoint(
        points: offsetPoints,
        segmentIndex: segmentIndex,
        t: 0.5,
      );
      if (curvePoint != null) {
        return DrawPoint(x: curvePoint.dx, y: curvePoint.dy);
      }
    }

    // For straight arrows, use linear midpoint
    return _midpoint(points[segmentIndex], points[segmentIndex + 1]);
  }

  static DrawPoint _midpoint(DrawPoint a, DrawPoint b) =>
      DrawPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

  static bool _isSegmentTooShort(
    DrawPoint start,
    DrawPoint end,
    double? handleSize,
  ) {
    if (handleSize == null || handleSize <= 0) {
      return false;
    }
    final length = start.distance(end);
    return length < handleSize * 0.5;
  }
}
