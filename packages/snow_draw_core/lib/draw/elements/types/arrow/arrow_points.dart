import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';
import 'arrow_elbow_line_binding_adjuster.dart';

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
    required this.addableBendControls,
  });

  final List<ArrowPointHandle> turningPoints;
  final List<ArrowPointHandle> addablePoints;
  final List<ArrowPointHandle> loopPoints;
  final List<bool> addableBendControls;

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
        addableBendControls: [],
      );
    }

    final rawPoints = _resolveWorldPoints(element, data);
    if (rawPoints.length < 2) {
      return const ArrowPointOverlay(
        turningPoints: [],
        addablePoints: [],
        loopPoints: [],
        addableBendControls: [],
      );
    }

    final segmentPoints = _resolveSegmentPoints(rawPoints, data);

    final isElbowLine = data.arrowType == ArrowType.elbowLine;
    final loopActive =
        rawPoints.first.distanceSquared(rawPoints.last) <=
        loopThreshold * loopThreshold;

    final turningPoints = <ArrowPointHandle>[];
    if (isElbowLine) {
      if (!loopActive) {
        turningPoints
          ..add(
            ArrowPointHandle(
              elementId: element.id,
              kind: ArrowPointKind.turning,
              index: 0,
              position: rawPoints.first,
            ),
          )
          ..add(
            ArrowPointHandle(
              elementId: element.id,
              kind: ArrowPointKind.turning,
              index: rawPoints.length - 1,
              position: rawPoints.last,
            ),
          );
      }
    } else {
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
    final addableBendControls =
        isElbowLine
            ? resolveElbowLineBendControlSegments(
                elementId: element.id,
                data: data,
                rawPoints: rawPoints,
                segmentPoints: segmentPoints,
              )
            : List<bool>.filled(segmentPoints.length - 1, false);

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
      addableBendControls: List<bool>.unmodifiable(addableBendControls),
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

    final segmentPoints = _resolveSegmentPoints(rawPoints, data);

    final localPosition = _toLocalPosition(element, position);
    final visualPointRadius = handleSize == null || handleSize <= 0
        ? 0.0
        : handleSize * 0.5;
    final visualLoopOuterRadius = handleSize == null || handleSize <= 0
        ? 0.0
        : handleSize * 1.0;
    final visualLoopInnerRadius = visualPointRadius;
    final isElbowLine = data.arrowType == ArrowType.elbowLine;
    final loopActive =
        rawPoints.first.distanceSquared(rawPoints.last) <=
        loopThreshold * loopThreshold;

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
    if (isElbowLine) {
      if (!loopActive) {
        final endpoints = <int>[0, rawPoints.length - 1];
        for (final i in endpoints) {
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
      }
    } else {
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
    final effective = data.arrowType == ArrowType.elbowLine
        ? ArrowGeometry.expandElbowLinePoints(resolved, includeVirtual: false)
        : resolved;
    return effective
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
  }

  static List<DrawPoint> _resolveSegmentPoints(
    List<DrawPoint> rawPoints,
    ArrowData data,
  ) {
    if (data.arrowType != ArrowType.elbowLine) {
      return rawPoints;
    }
    if (rawPoints.length < 2) {
      return rawPoints;
    }
    final offsets = rawPoints
        .map((point) => Offset(point.x, point.y))
        .toList(growable: false);
    final expanded = ArrowGeometry.expandElbowLinePoints(offsets);
    return expanded
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
  }

  static List<bool> resolveElbowLineBendControlSegments({
    required String elementId,
    required ArrowData data,
    required List<DrawPoint> rawPoints,
    required List<DrawPoint> segmentPoints,
  }) {
    final segmentCount = segmentPoints.length - 1;
    if (segmentCount <= 0) {
      return const [];
    }
    final rawSegmentCount = rawPoints.length - 1;
    if (rawSegmentCount <= 0) {
      return List<bool>.filled(segmentCount, false);
    }
    final autoPointIndices =
        (data.startBinding == null && data.endBinding == null)
            ? const <int>{}
            : resolveElbowLineBindingAutoPoints(elementId);
    final userPointIndices = <int>[];
    for (var i = 0; i < rawPoints.length; i++) {
      if (i == 0 ||
          i == rawPoints.length - 1 ||
          !autoPointIndices.contains(i)) {
        userPointIndices.add(i);
      }
    }
    if (userPointIndices.length < 2) {
      return List<bool>.filled(segmentCount, false);
    }

    final rawToUserSegment =
        List<int>.filled(rawSegmentCount, 0, growable: false);
    var userSegmentIndex = 0;
    for (var rawIndex = 0; rawIndex < rawSegmentCount; rawIndex++) {
      while (userSegmentIndex + 1 < userPointIndices.length &&
          rawIndex >= userPointIndices[userSegmentIndex + 1]) {
        userSegmentIndex++;
      }
      rawToUserSegment[rawIndex] = userSegmentIndex;
    }

    final segmentMap = _resolveElbowLineSegmentMap(
      rawPoints: rawPoints,
      segmentPoints: segmentPoints,
    );
    final lastUserSegmentIndex = userPointIndices.length - 2;
    return List<bool>.generate(segmentCount, (index) {
      if (index < 0 || index >= segmentMap.length) {
        return false;
      }
      final rawIndex = segmentMap[index];
      if (rawIndex < 0 || rawIndex >= rawToUserSegment.length) {
        return false;
      }
      final resolvedUserSegment = rawToUserSegment[rawIndex];
      return resolvedUserSegment > 0 &&
          resolvedUserSegment < lastUserSegmentIndex;
    });
  }

  static List<int> _resolveElbowLineSegmentMap({
    required List<DrawPoint> rawPoints,
    required List<DrawPoint> segmentPoints,
  }) {
    final segmentCount = segmentPoints.length - 1;
    final mapping = List<int>.filled(segmentCount, -1);
    if (rawPoints.length < 2 || segmentCount <= 0) {
      return mapping;
    }
    const epsilon = 1e-6;
    bool matches(DrawPoint a, DrawPoint b) =>
        (a.x - b.x).abs() <= epsilon && (a.y - b.y).abs() <= epsilon;

    var expandedIndex = 0;
    for (var rawIndex = 0; rawIndex < rawPoints.length - 1; rawIndex++) {
      final start = rawPoints[rawIndex];
      while (expandedIndex < segmentPoints.length &&
          !matches(segmentPoints[expandedIndex], start)) {
        expandedIndex++;
      }
      if (expandedIndex >= segmentPoints.length - 1) {
        break;
      }

      final end = rawPoints[rawIndex + 1];
      var endIndex = expandedIndex + 1;
      while (endIndex < segmentPoints.length &&
          !matches(segmentPoints[endIndex], end)) {
        endIndex++;
      }
      if (endIndex >= segmentPoints.length) {
        break;
      }

      for (var segmentIndex = expandedIndex;
          segmentIndex < endIndex;
          segmentIndex++) {
        mapping[segmentIndex] = rawIndex;
      }
      expandedIndex = endIndex;
    }
    return mapping;
  }

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
  /// For straight and elbow line arrows, this uses linear interpolation.
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

    // For straight and elbow line arrows, use linear midpoint
    return _midpoint(points[segmentIndex], points[segmentIndex + 1]);
  }

  static DrawPoint _midpoint(DrawPoint a, DrawPoint b) =>
      DrawPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);
}



