import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_geometry_adapter.dart';
import 'arrow_focus.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

enum ConnectorPointKind {
  turning,
  addable,
  loopStart,
  loopEnd,
  focusStart,
  focusEnd,
}

@immutable
class ConnectorPointHandle {
  const ConnectorPointHandle({
    required this.elementId,
    required this.kind,
    required this.index,
    required this.position,
    this.isFixed = false,
  });

  /// Element id that owns this control point.
  final String elementId;

  /// Control point kind.
  final ConnectorPointKind kind;

  /// Turning point index (or segment start index for addable points).
  final int index;

  /// World-space position in the element's un-rotated coordinate space.
  final DrawPoint position;

  /// Whether the handle represents a fixed elbow segment.
  final bool isFixed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectorPointHandle &&
          other.elementId == elementId &&
          other.kind == kind &&
          other.index == index &&
          other.isFixed == isFixed;

  @override
  int get hashCode => Object.hash(elementId, kind, index, isFixed);

  @override
  String toString() =>
      'ConnectorPointHandle(id: $elementId, kind: $kind, index: $index, '
      'isFixed: $isFixed)';
}

@immutable
class ConnectorPointOverlay {
  const ConnectorPointOverlay({
    required this.turningPoints,
    required this.addablePoints,
    required this.loopPoints,
    required this.focusPoints,
  });

  final List<ConnectorPointHandle> turningPoints;
  final List<ConnectorPointHandle> addablePoints;
  final List<ConnectorPointHandle> loopPoints;
  final List<ConnectorPointHandle> focusPoints;

  bool get hasLoop => loopPoints.isNotEmpty;
  bool get hasFocus => focusPoints.isNotEmpty;
}

class ConnectorPointUtils {
  const ConnectorPointUtils._();

  static const _emptyOverlay = ConnectorPointOverlay(
    turningPoints: [],
    addablePoints: [],
    loopPoints: [],
    focusPoints: [],
  );
  static const _turningHitRadiusFactor = 1.11;
  static const _addableHitRadiusFactor = 1.43;
  static const _loopOuterHitRadiusFactor = 1.18;
  static const _loopInnerHitRadiusFactor = 0.69;

  static ConnectorPointOverlay buildOverlay({
    required ElementState element,
    required double loopThreshold,
    double? handleSize,
    Iterable<ElementState> elements = const <ElementState>[],
    double zoom = 1,
    bool isBindingEnabled = true,
  }) {
    final data = element.data;
    if (data is! ConnectorData) {
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

    final overlay = _buildPathOverlay(
      elementId: element.id,
      points: points,
      arrowType: data.arrowType,
      loopThreshold: loopThreshold,
    );
    final focusPoints = _buildFocusPoints(
      element: element,
      data: data,
      elements: elements,
      zoom: zoom,
      isBindingEnabled: isBindingEnabled,
    );
    if (focusPoints.isEmpty) {
      return overlay;
    }

    final hasStartFocus = focusPoints.any(
      (handle) => handle.kind == ConnectorPointKind.focusStart,
    );
    final hasEndFocus = focusPoints.any(
      (handle) => handle.kind == ConnectorPointKind.focusEnd,
    );
    final filteredTurningPoints = overlay.turningPoints
        .where((handle) {
          if (handle.kind != ConnectorPointKind.turning) {
            return true;
          }
          if (hasStartFocus && handle.index == 0) {
            return false;
          }
          if (hasEndFocus && handle.index == points.length - 1) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return ConnectorPointOverlay(
      turningPoints: List<ConnectorPointHandle>.unmodifiable(
        filteredTurningPoints,
      ),
      addablePoints: overlay.addablePoints,
      loopPoints: overlay.loopPoints,
      focusPoints: focusPoints,
    );
  }

  static ConnectorPointHandle? hitTest({
    required ElementState element,
    required DrawPoint position,
    required double hitRadius,
    required double loopThreshold,
    double? handleSize,
    Iterable<ElementState> elements = const <ElementState>[],
    double zoom = 1,
    bool isBindingEnabled = true,
  }) {
    final data = element.data;
    if (data is! ConnectorData) {
      return null;
    }
    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      return null;
    }

    final localPosition = _toLocalPosition(element, position);
    final visualPointRadius = _resolveVisualRadius(handleSize, 0.5);
    final loopActive = _isLoopActive(points, loopThreshold);
    final focusPoints = data.arrowType == ArrowType.elbow
        ? const <ConnectorPointHandle>[]
        : _buildFocusPoints(
            element: element,
            data: data,
            elements: elements,
            zoom: zoom,
            isBindingEnabled: isBindingEnabled,
          );

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

    final focusHit = _hitTestFocusPoints(
      focusPoints: focusPoints,
      localPosition: localPosition,
      hitRadius: _maxRadius(
        hitRadius * _turningHitRadiusFactor,
        visualPointRadius,
      ),
    );
    if (focusHit != null) {
      return focusHit;
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
        return ConnectorPointHandle(
          elementId: element.id,
          kind: ConnectorPointKind.addable,
          index: i,
          position: midpoint,
        );
      }
    }

    return null;
  }

  static ConnectorPointOverlay _buildElbowOverlay({
    required String elementId,
    required List<DrawPoint> points,
    required List<ElbowFixedSegment>? fixedSegments,
    required double? handleSize,
  }) {
    final turningPoints = List<ConnectorPointHandle>.unmodifiable([
      ConnectorPointHandle(
        elementId: elementId,
        kind: ConnectorPointKind.turning,
        index: 0,
        position: points.first,
      ),
      ConnectorPointHandle(
        elementId: elementId,
        kind: ConnectorPointKind.turning,
        index: points.length - 1,
        position: points.last,
      ),
    ]);
    final fixedSegmentIndexes = _fixedSegmentIndexSet(fixedSegments);
    final addablePoints = <ConnectorPointHandle>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (_isSegmentTooShort(start, end, handleSize)) {
        continue;
      }
      addablePoints.add(
        ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.addable,
          index: i,
          position: _midpoint(start, end),
          isFixed: fixedSegmentIndexes.contains(i + 1),
        ),
      );
    }
    return ConnectorPointOverlay(
      turningPoints: turningPoints,
      addablePoints: List<ConnectorPointHandle>.unmodifiable(addablePoints),
      loopPoints: const [],
      focusPoints: const [],
    );
  }

  static ConnectorPointOverlay _buildPathOverlay({
    required String elementId,
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required double loopThreshold,
  }) {
    final loopActive = _isLoopActive(points, loopThreshold);

    final turningPoints = <ConnectorPointHandle>[];
    for (var i = 0; i < points.length; i++) {
      if (loopActive && (i == 0 || i == points.length - 1)) {
        continue;
      }
      turningPoints.add(
        ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.turning,
          index: i,
          position: points[i],
        ),
      );
    }

    final addablePoints = <ConnectorPointHandle>[];
    for (var i = 0; i < points.length - 1; i++) {
      addablePoints.add(
        ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.addable,
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
        ? <ConnectorPointHandle>[
            ConnectorPointHandle(
              elementId: elementId,
              kind: ConnectorPointKind.loopStart,
              index: 0,
              position: points.first,
            ),
            ConnectorPointHandle(
              elementId: elementId,
              kind: ConnectorPointKind.loopEnd,
              index: points.length - 1,
              position: points.last,
            ),
          ]
        : const <ConnectorPointHandle>[];

    return ConnectorPointOverlay(
      turningPoints: List<ConnectorPointHandle>.unmodifiable(turningPoints),
      addablePoints: List<ConnectorPointHandle>.unmodifiable(addablePoints),
      loopPoints: List<ConnectorPointHandle>.unmodifiable(loopPoints),
      focusPoints: const [],
    );
  }

  static ConnectorPointHandle? _hitTestElbow({
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
        return ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.addable,
          index: i,
          position: midpoint,
          isFixed: fixedSegmentIndexes.contains(i + 1),
        );
      }
    }
    return null;
  }

  static ConnectorPointHandle? _hitTestElbowTurningPoints({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
  }) {
    final hitRadiusSq = hitRadius * hitRadius;
    ConnectorPointHandle? nearest;
    var nearestDistanceSq = double.infinity;

    void testPoint(int index, DrawPoint point) {
      final distanceSq = localPosition.distanceSquared(point);
      if (distanceSq <= hitRadiusSq && distanceSq < nearestDistanceSq) {
        nearestDistanceSq = distanceSq;
        nearest = ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.turning,
          index: index,
          position: point,
        );
      }
    }

    testPoint(0, points.first);
    testPoint(points.length - 1, points.last);
    return nearest;
  }

  static ConnectorPointHandle? _hitTestLoop({
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
      return ConnectorPointHandle(
        elementId: elementId,
        kind: ConnectorPointKind.loopStart,
        index: 0,
        position: points.first,
      );
    }

    final outerRadius = _maxRadius(
      hitRadius * _loopOuterHitRadiusFactor,
      visualLoopOuterRadius,
    );
    if (distanceSq <= outerRadius * outerRadius) {
      return ConnectorPointHandle(
        elementId: elementId,
        kind: ConnectorPointKind.loopEnd,
        index: points.length - 1,
        position: points.last,
      );
    }

    return null;
  }

  static ConnectorPointHandle? _hitTestTurningPoints({
    required String elementId,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double hitRadius,
    required bool skipEndpoints,
  }) {
    final hitRadiusSq = hitRadius * hitRadius;
    ConnectorPointHandle? nearest;
    var nearestDistanceSq = double.infinity;
    for (var i = 0; i < points.length; i++) {
      if (skipEndpoints && (i == 0 || i == points.length - 1)) {
        continue;
      }
      final point = points[i];
      final distanceSq = localPosition.distanceSquared(point);
      if (distanceSq <= hitRadiusSq && distanceSq < nearestDistanceSq) {
        nearestDistanceSq = distanceSq;
        nearest = ConnectorPointHandle(
          elementId: elementId,
          kind: ConnectorPointKind.turning,
          index: i,
          position: point,
        );
      }
    }
    return nearest;
  }

  static ConnectorPointHandle? _hitTestFocusPoints({
    required List<ConnectorPointHandle> focusPoints,
    required DrawPoint localPosition,
    required double hitRadius,
  }) {
    if (focusPoints.isEmpty) {
      return null;
    }
    final hitRadiusSq = hitRadius * hitRadius;
    ConnectorPointHandle? nearest;
    var nearestDistanceSq = double.infinity;
    for (final handle in focusPoints) {
      final distanceSq = localPosition.distanceSquared(handle.position);
      if (distanceSq > hitRadiusSq || distanceSq >= nearestDistanceSq) {
        continue;
      }
      nearestDistanceSq = distanceSq;
      nearest = handle;
    }
    return nearest;
  }

  static List<DrawPoint> _resolveWorldPoints(
    ElementState element,
    ConnectorData data,
  ) => resolveArrowWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );

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

  static List<ConnectorPointHandle> _buildFocusPoints({
    required ElementState element,
    required ConnectorData data,
    required Iterable<ElementState> elements,
    required double zoom,
    required bool isBindingEnabled,
  }) {
    if (data.arrowType == ArrowType.elbow || elements.isEmpty) {
      return const <ConnectorPointHandle>[];
    }

    final focusPoints = listVisibleArrowFocusPoints(
      element: element,
      data: data,
      elements: elements,
      engineContext: buildCoreEngineContext(
        zoom: zoom,
        isBindingEnabled: isBindingEnabled,
      ),
    );
    if (focusPoints.isEmpty) {
      return const <ConnectorPointHandle>[];
    }

    final pointCount = data.points.length;
    final handles = <ConnectorPointHandle>[];
    for (final focusPoint in focusPoints) {
      final kind = switch (focusPoint.endpoint) {
        ArrowFocusEndpoint.start => ConnectorPointKind.focusStart,
        ArrowFocusEndpoint.end => ConnectorPointKind.focusEnd,
      };
      final index = kind == ConnectorPointKind.focusStart ? 0 : pointCount - 1;
      final localPosition = _toLocalPosition(element, focusPoint.position);
      handles.add(
        ConnectorPointHandle(
          elementId: element.id,
          kind: kind,
          index: index,
          position: localPosition,
        ),
      );
    }
    return List<ConnectorPointHandle>.unmodifiable(handles);
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
      final curvePoint = ConnectorGeometry.calculateCurveDrawPoint(
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
