import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

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

  static const _emptyOverlay = ArrowPointOverlay(
    turningPoints: [],
    addablePoints: [],
    loopPoints: [],
  );
  static const _turningHitRadiusFactor = 1.11;
  static const _addableHitRadiusFactor = 1.43;
  static const _loopOuterHitRadiusFactor = 1.18;
  static const _loopInnerHitRadiusFactor = 0.69;

  static ArrowPointOverlay buildOverlay({
    required ElementState element,
    required double loopThreshold,
    double? handleSize,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      return _emptyOverlay;
    }

    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      return _emptyOverlay;
    }

    if (data.arrowType == ArrowType.elbow) {
      return _buildElbowOverlay(
        elementId: element.id,
        points: points,
        fixedSegments: data.fixedSegments,
        handleSize: handleSize,
      );
    }

    return _buildPathOverlay(
      elementId: element.id,
      points: points,
      arrowType: data.arrowType,
      loopThreshold: loopThreshold,
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
    if (data is! ArrowLikeData) {
      return null;
    }
    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      return null;
    }

    final localPosition = _toLocalPosition(element, position);
    final visualPointRadius = _resolveVisualRadius(handleSize, 0.5);
    final loopActive = _isLoopActive(points, loopThreshold);

    if (data.arrowType == ArrowType.elbow) {
      return _hitTestElbow(
        elementId: element.id,
        points: points,
        localPosition: localPosition,
        hitRadius: hitRadius,
        visualPointRadius: visualPointRadius,
        handleSize: handleSize,
        fixedSegments: data.fixedSegments,
      );
    }

    final loopHit = _hitTestLoop(
      elementId: element.id,
      points: points,
      localPosition: localPosition,
      hitRadius: hitRadius,
      visualPointRadius: visualPointRadius,
      visualLoopOuterRadius: _resolveVisualRadius(handleSize, 1),
      loopActive: loopActive,
    );
    if (loopHit != null) {
      return loopHit;
    }

    final turningHit = _hitTestTurningPoints(
      elementId: element.id,
      points: points,
      localPosition: localPosition,
      hitRadius: _maxRadius(
        hitRadius * _turningHitRadiusFactor,
        visualPointRadius,
      ),
      skipEndpoints: loopActive,
    );
    if (turningHit != null) {
      return turningHit;
    }

    final addableHitRadius = _maxRadius(
      hitRadius * _addableHitRadiusFactor,
      visualPointRadius,
    );
    final addableHitRadiusSq = addableHitRadius * addableHitRadius;
    for (var i = 0; i < points.length - 1; i++) {
      final midpoint = _segmentMidpoint(
        points: points,
        arrowType: data.arrowType,
        segmentIndex: i,
      );
      final distanceSq = localPosition.distanceSquared(midpoint);
      if (distanceSq <= addableHitRadiusSq) {
        return ArrowPointHandle(
          elementId: element.id,
          kind: ArrowPointKind.addable,
          index: i,
          position: midpoint,
        );
      }
    }

    return null;
  }

  static ArrowPointOverlay _buildElbowOverlay({
    required String elementId,
    required List<DrawPoint> points,
    required List<ElbowFixedSegment>? fixedSegments,
    required double? handleSize,
  }) {
    final turningPoints = List<ArrowPointHandle>.unmodifiable([
      ArrowPointHandle(
        elementId: elementId,
        kind: ArrowPointKind.turning,
        index: 0,
        position: points.first,
      ),
      ArrowPointHandle(
        elementId: elementId,
        kind: ArrowPointKind.turning,
        index: points.length - 1,
        position: points.last,
      ),
    ]);
    final fixedSegmentIndexes = _fixedSegmentIndexSet(fixedSegments);
    final addablePoints = <ArrowPointHandle>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (_isSegmentTooShort(start, end, handleSize)) {
        continue;
      }
      addablePoints.add(
        ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.addable,
          index: i,
          position: _midpoint(start, end),
          isFixed: fixedSegmentIndexes.contains(i + 1),
        ),
      );
    }
    return ArrowPointOverlay(
      turningPoints: turningPoints,
      addablePoints: List<ArrowPointHandle>.unmodifiable(addablePoints),
      loopPoints: const [],
    );
  }

  static ArrowPointOverlay _buildPathOverlay({
    required String elementId,
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required double loopThreshold,
  }) {
    final loopActive = _isLoopActive(points, loopThreshold);

    final turningPoints = <ArrowPointHandle>[];
    for (var i = 0; i < points.length; i++) {
      if (loopActive && (i == 0 || i == points.length - 1)) {
        continue;
      }
      turningPoints.add(
        ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.turning,
          index: i,
          position: points[i],
        ),
      );
    }

    final addablePoints = <ArrowPointHandle>[];
    for (var i = 0; i < points.length - 1; i++) {
      addablePoints.add(
        ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.addable,
          index: i,
          position: _segmentMidpoint(
            points: points,
            arrowType: arrowType,
            segmentIndex: i,
          ),
        ),
      );
    }

    final loopPoints = loopActive
        ? <ArrowPointHandle>[
            ArrowPointHandle(
              elementId: elementId,
              kind: ArrowPointKind.loopStart,
              index: 0,
              position: points.first,
            ),
            ArrowPointHandle(
              elementId: elementId,
              kind: ArrowPointKind.loopEnd,
              index: points.length - 1,
              position: points.last,
            ),
          ]
        : const <ArrowPointHandle>[];

    return ArrowPointOverlay(
      turningPoints: List<ArrowPointHandle>.unmodifiable(turningPoints),
      addablePoints: List<ArrowPointHandle>.unmodifiable(addablePoints),
      loopPoints: List<ArrowPointHandle>.unmodifiable(loopPoints),
    );
  }

  static ArrowPointHandle? _hitTestElbow({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
    required double visualPointRadius,
    required double? handleSize,
    required List<ElbowFixedSegment>? fixedSegments,
  }) {
    final turningHit = _hitTestElbowTurningPoints(
      elementId: elementId,
      points: points,
      localPosition: localPosition,
      hitRadius: _maxRadius(
        hitRadius * _turningHitRadiusFactor,
        visualPointRadius,
      ),
    );
    if (turningHit != null) {
      return turningHit;
    }

    final fixedSegmentIndexes = _fixedSegmentIndexSet(fixedSegments);
    final segmentHitRadiusSq = hitRadius * hitRadius;
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (_isSegmentTooShort(start, end, handleSize)) {
        continue;
      }
      final midpoint = _midpoint(start, end);
      final distanceSq = localPosition.distanceSquared(midpoint);
      if (distanceSq <= segmentHitRadiusSq) {
        return ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.addable,
          index: i,
          position: midpoint,
          isFixed: fixedSegmentIndexes.contains(i + 1),
        );
      }
    }
    return null;
  }

  static ArrowPointHandle? _hitTestElbowTurningPoints({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
  }) {
    final hitRadiusSq = hitRadius * hitRadius;
    ArrowPointHandle? nearest;
    var nearestDistanceSq = double.infinity;

    void testPoint(int index, DrawPoint point) {
      final distanceSq = localPosition.distanceSquared(point);
      if (distanceSq <= hitRadiusSq && distanceSq < nearestDistanceSq) {
        nearestDistanceSq = distanceSq;
        nearest = ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.turning,
          index: index,
          position: point,
        );
      }
    }

    testPoint(0, points.first);
    testPoint(points.length - 1, points.last);
    return nearest;
  }

  static ArrowPointHandle? _hitTestLoop({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
    required double visualPointRadius,
    required double visualLoopOuterRadius,
    required bool loopActive,
  }) {
    if (!loopActive) {
      return null;
    }

    final loopCenter = _midpoint(points.first, points.last);
    final distanceSq = localPosition.distanceSquared(loopCenter);

    final innerRadius = _maxRadius(
      hitRadius * _loopInnerHitRadiusFactor,
      visualPointRadius,
    );
    if (distanceSq <= innerRadius * innerRadius) {
      return ArrowPointHandle(
        elementId: elementId,
        kind: ArrowPointKind.loopStart,
        index: 0,
        position: points.first,
      );
    }

    final outerRadius = _maxRadius(
      hitRadius * _loopOuterHitRadiusFactor,
      visualLoopOuterRadius,
    );
    if (distanceSq <= outerRadius * outerRadius) {
      return ArrowPointHandle(
        elementId: elementId,
        kind: ArrowPointKind.loopEnd,
        index: points.length - 1,
        position: points.last,
      );
    }

    return null;
  }

  static ArrowPointHandle? _hitTestTurningPoints({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
    required bool skipEndpoints,
  }) {
    final hitRadiusSq = hitRadius * hitRadius;
    ArrowPointHandle? nearest;
    var nearestDistanceSq = double.infinity;
    for (var i = 0; i < points.length; i++) {
      if (skipEndpoints && (i == 0 || i == points.length - 1)) {
        continue;
      }
      final point = points[i];
      final distanceSq = localPosition.distanceSquared(point);
      if (distanceSq <= hitRadiusSq && distanceSq < nearestDistanceSq) {
        nearestDistanceSq = distanceSq;
        nearest = ArrowPointHandle(
          elementId: elementId,
          kind: ArrowPointKind.turning,
          index: i,
          position: point,
        );
      }
    }
    return nearest;
  }

  static List<DrawPoint> _resolveWorldPoints(
    ElementState element,
    ArrowLikeData data,
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
    final space = ElementSpace(
      rotation: element.rotation,
      origin: element.rect.center,
    );
    return space.fromWorld(position);
  }

  static DrawPoint _segmentMidpoint({
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required int segmentIndex,
  }) {
    assert(
      segmentIndex >= 0 && segmentIndex < points.length - 1,
      'segmentIndex must reference a valid segment in points.',
    );
    if (arrowType == ArrowType.curved && points.length >= 3) {
      final curvePoint = ArrowGeometry.calculateCurveDrawPoint(
        points: points,
        segmentIndex: segmentIndex,
        t: 0.5,
      );
      if (curvePoint != null) {
        return curvePoint;
      }
    }
    return _midpoint(points[segmentIndex], points[segmentIndex + 1]);
  }

  static DrawPoint _midpoint(DrawPoint a, DrawPoint b) =>
      DrawPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

  static bool _isLoopActive(List<DrawPoint> points, double loopThreshold) =>
      points.first.distanceSquared(points.last) <=
      loopThreshold * loopThreshold;

  static double _resolveVisualRadius(double? handleSize, double multiplier) {
    if (handleSize == null || handleSize <= 0) {
      return 0;
    }
    return handleSize * multiplier;
  }

  static double _maxRadius(double radius, double visualRadius) =>
      visualRadius > radius ? visualRadius : radius;

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

  static Set<int> _fixedSegmentIndexSet(
    List<ElbowFixedSegment>? fixedSegments,
  ) {
    if (fixedSegments == null || fixedSegments.isEmpty) {
      return const <int>{};
    }
    return {for (final segment in fixedSegments) segment.index};
  }
}
