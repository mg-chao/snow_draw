import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../rectangle/rectangle_data.dart';

enum ArrowBindingMode { inside, orbit }

@immutable
final class ArrowBinding {
  const ArrowBinding({
    required this.elementId,
    required this.anchor,
    this.mode = ArrowBindingMode.orbit,
  });

  factory ArrowBinding.fromJson(Map<String, dynamic> json) {
    final elementId = json['elementId'] as String?;
    final anchorJson = json['anchor'];
    if (elementId == null || anchorJson is! Map) {
      throw const FormatException('Invalid ArrowBinding payload');
    }
    final x = (anchorJson['x'] as num?)?.toDouble() ?? 0.0;
    final y = (anchorJson['y'] as num?)?.toDouble() ?? 0.0;
    final mode = ArrowBindingMode.values.firstWhere(
      (value) => value.name == json['mode'],
      orElse: () => ArrowBindingMode.orbit,
    );
    return ArrowBinding(
      elementId: elementId,
      anchor: DrawPoint(x: _clamp01(x), y: _clamp01(y)),
      mode: mode,
    );
  }

  final String elementId;

  /// Normalized anchor in the target element's unrotated rect (0..1).
  final DrawPoint anchor;
  final ArrowBindingMode mode;

  ArrowBinding copyWith({
    String? elementId,
    DrawPoint? anchor,
    ArrowBindingMode? mode,
  }) => ArrowBinding(
    elementId: elementId ?? this.elementId,
    anchor: anchor ?? this.anchor,
    mode: mode ?? this.mode,
  );

  Map<String, dynamic> toJson() => {
    'elementId': elementId,
    'anchor': {'x': anchor.x, 'y': anchor.y},
    'mode': mode.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowBinding &&
          other.elementId == elementId &&
          other.anchor == anchor &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(elementId, anchor, mode);
}

@immutable
final class ArrowBindingResult {
  const ArrowBindingResult({
    required this.binding,
    required this.snapPoint,
    required this.distance,
    required this.zIndex,
  });

  final ArrowBinding binding;
  final DrawPoint snapPoint;
  final double distance;
  final int zIndex;
}

class ArrowBindingUtils {
  const ArrowBindingUtils._();

  static double resolveBindingSearchDistance(double snapDistance) =>
      snapDistance * (1 + _bindingHitToleranceFactor);

  static ArrowBindingResult? resolveBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    ArrowBinding? preferredBinding,
    bool allowNewBinding = true,
    DrawPoint? referencePoint,
  }) {
    if (snapDistance <= 0) {
      return null;
    }
    if (!allowNewBinding && preferredBinding == null) {
      return null;
    }

    ArrowBindingResult? best;
    var bestScore = double.infinity;

    for (final target in targets) {
      if (target.opacity <= 0) {
        continue;
      }
      if (!allowNewBinding &&
          preferredBinding != null &&
          target.id != preferredBinding.elementId) {
        continue;
      }

      final result = _resolveBindingOnTarget(
        target: target,
        worldPoint: worldPoint,
        snapDistance: snapDistance,
        referencePoint: referencePoint,
      );
      if (result == null) {
        continue;
      }

      var score = result.distance;
      if (preferredBinding != null && preferredBinding.elementId == target.id) {
        score = math.max(0, score - snapDistance * 0.25);
      }

      if (score < bestScore ||
          (score == bestScore && result.zIndex > (best?.zIndex ?? -1))) {
        best = result;
        bestScore = score;
      }
    }

    return best;
  }

  static DrawPoint? resolveBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    DrawPoint? referencePoint,
  }) {
    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }
    final localAnchor = DrawPoint(
      x: rect.minX + rect.width * binding.anchor.x,
      y: rect.minY + rect.height * binding.anchor.y,
    );
    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    if (binding.mode == ArrowBindingMode.inside) {
      return space.toWorld(localAnchor);
    }

    final gap = _resolveBindingGap(target);
    final localReference = referencePoint == null
        ? null
        : space.fromWorld(referencePoint);
    final snapPoint = _resolveOrbitSnapPoint(
      rect: rect,
      anchorPoint: localAnchor,
      localReference: localReference,
      gap: gap,
    );
    return space.toWorld(snapPoint);
  }

  static ArrowBinding? bindingFromLocalPoint({
    required ElementState target,
    required DrawPoint localPoint,
    ArrowBindingMode mode = ArrowBindingMode.orbit,
  }) {
    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }
    final normalized = DrawPoint(
      x: rect.width == 0 ? 0.0 : (localPoint.x - rect.minX) / rect.width,
      y: rect.height == 0 ? 0.0 : (localPoint.y - rect.minY) / rect.height,
    );
    return ArrowBinding(
      elementId: target.id,
      anchor: DrawPoint(x: _clamp01(normalized.x), y: _clamp01(normalized.y)),
      mode: mode,
    );
  }

  static ArrowBindingResult? _resolveBindingOnTarget({
    required ElementState target,
    required DrawPoint worldPoint,
    required double snapDistance,
    DrawPoint? referencePoint,
  }) {
    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }

    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    final localPoint = space.fromWorld(worldPoint);
    final localReference = referencePoint == null
        ? null
        : space.fromWorld(referencePoint);
    final hit = _resolveBindingHit(
      rect: rect,
      localPoint: localPoint,
      localReference: localReference,
      snapDistance: snapDistance,
      gap: _resolveBindingGap(target),
    );
    if (hit == null) {
      return null;
    }

    final binding = bindingFromLocalPoint(
      target: target,
      localPoint: hit.anchorPoint,
      mode: hit.mode,
    );
    if (binding == null) {
      return null;
    }

    return ArrowBindingResult(
      binding: binding,
      snapPoint: space.toWorld(hit.snapPoint),
      distance: hit.distance,
      zIndex: target.zIndex,
    );
  }
}

@immutable
final class _BindingHit {
  const _BindingHit({
    required this.anchorPoint,
    required this.snapPoint,
    required this.mode,
    required this.distance,
  });

  final DrawPoint anchorPoint;
  final DrawPoint snapPoint;
  final ArrowBindingMode mode;
  final double distance;
}

const _bindingGapBase = 6.0;
const _bindingHitToleranceFactor = 0.4;
const _intersectionEpsilon = 1e-6;
const _insideEpsilon = 1e-6;

double _resolveInsideBindingThreshold({
  required DrawRect rect,
  required double snapDistance,
}) {
  if (snapDistance <= 0) {
    return 0;
  }
  final maxDepth = math.min(rect.width.abs(), rect.height.abs()) / 2;
  if (maxDepth <= 0) {
    return 0;
  }
  return math.min(snapDistance, maxDepth);
}

double _resolveInsideDepth(DrawRect rect, DrawPoint point) {
  final left = (point.x - rect.minX).abs();
  final right = (rect.maxX - point.x).abs();
  final top = (point.y - rect.minY).abs();
  final bottom = (rect.maxY - point.y).abs();
  return math.min(math.min(left, right), math.min(top, bottom));
}

DrawPoint _nearestPointOnRectBoundary(DrawRect rect, DrawPoint point) {
  final clampedX = _clamp(point.x, rect.minX, rect.maxX);
  final clampedY = _clamp(point.y, rect.minY, rect.maxY);

  final inside =
      point.x >= rect.minX &&
      point.x <= rect.maxX &&
      point.y >= rect.minY &&
      point.y <= rect.maxY;
  if (!inside) {
    return DrawPoint(x: clampedX, y: clampedY);
  }

  final left = (point.x - rect.minX).abs();
  final right = (rect.maxX - point.x).abs();
  final top = (point.y - rect.minY).abs();
  final bottom = (rect.maxY - point.y).abs();

  final minDistance = math.min(math.min(left, right), math.min(top, bottom));
  if (minDistance == left) {
    return DrawPoint(x: rect.minX, y: point.y);
  }
  if (minDistance == right) {
    return DrawPoint(x: rect.maxX, y: point.y);
  }
  if (minDistance == top) {
    return DrawPoint(x: point.x, y: rect.minY);
  }
  return DrawPoint(x: point.x, y: rect.maxY);
}

double _resolveBindingGap(ElementState target) {
  final data = target.data;
  final strokeWidth = data is RectangleData ? data.strokeWidth : 0.0;
  return _bindingGapBase + strokeWidth / 2;
}

DrawRect _inflateRect(DrawRect rect, double delta) => DrawRect(
  minX: rect.minX - delta,
  minY: rect.minY - delta,
  maxX: rect.maxX + delta,
  maxY: rect.maxY + delta,
);

_BindingHit? _resolveBindingHit({
  required DrawRect rect,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
  required double snapDistance,
  required double gap,
}) {
  if (_isStrictlyInsideRect(rect, localPoint)) {
    final referenceInside =
        localReference != null && _isStrictlyInsideRect(rect, localReference);
    var allowInside = localReference == null || referenceInside;
    if (!allowInside) {
      final insideDepth = _resolveInsideDepth(rect, localPoint);
      final insideThreshold = _resolveInsideBindingThreshold(
        rect: rect,
        snapDistance: snapDistance,
      );
      allowInside = insideDepth >= insideThreshold;
    }
    if (allowInside) {
      final anchorPoint = _clampPointToRect(rect, localPoint);
      return _BindingHit(
        anchorPoint: anchorPoint,
        snapPoint: anchorPoint,
        mode: ArrowBindingMode.inside,
        distance: 0,
      );
    }

    final anchorPoint = _resolveOrbitAnchorPoint(
      rect: rect,
      localPoint: localPoint,
      localReference: localReference,
    );
    final snapPoint = _resolveOrbitSnapPoint(
      rect: rect,
      anchorPoint: anchorPoint,
      localReference: localReference,
      gap: gap,
      targetPoint: localPoint,
    );
    return _BindingHit(
      anchorPoint: anchorPoint,
      snapPoint: snapPoint,
      mode: ArrowBindingMode.orbit,
      distance: 0,
    );
  }

  final anchorPoint = _resolveOrbitAnchorPoint(
    rect: rect,
    localPoint: localPoint,
    localReference: localReference,
  );
  final distance = localPoint.distance(anchorPoint);
  if (distance > snapDistance * (1 + _bindingHitToleranceFactor)) {
    return null;
  }

  final snapPoint = _resolveOrbitSnapPoint(
    rect: rect,
    anchorPoint: anchorPoint,
    localReference: localReference,
    gap: gap,
    targetPoint: localPoint,
  );

  return _BindingHit(
    anchorPoint: anchorPoint,
    snapPoint: snapPoint,
    mode: ArrowBindingMode.orbit,
    distance: distance,
  );
}

DrawPoint _clampPointToRect(DrawRect rect, DrawPoint point) => DrawPoint(
  x: _clamp(point.x, rect.minX, rect.maxX),
  y: _clamp(point.y, rect.minY, rect.maxY),
);

// Prefer the intersection closest to the pointer so penetrations can bind.
DrawPoint _resolveOrbitAnchorPoint({
  required DrawRect rect,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
}) {
  if (localReference != null) {
    final intersection = _intersectRectAlongLine(
      rect: rect,
      reference: localReference,
      target: localPoint,
      preferPoint: localPoint,
    );
    if (intersection != null) {
      return intersection;
    }
  }
  return _nearestPointOnRectBoundary(rect, localPoint);
}

DrawPoint _resolveOrbitSnapPoint({
  required DrawRect rect,
  required DrawPoint anchorPoint,
  required DrawPoint? localReference,
  required double gap,
  DrawPoint? targetPoint,
}) {
  final snapRect = gap <= 0 ? rect : _inflateRect(rect, gap);
  final directionPoint = targetPoint ?? anchorPoint;

  if (localReference != null) {
    final intersection = _intersectRectAlongLine(
      rect: snapRect,
      reference: localReference,
      target: directionPoint,
      preferRay: true,
    );
    if (intersection != null) {
      return intersection;
    }
  }

  return _nearestPointOnRectBoundary(snapRect, directionPoint);
}

bool _isStrictlyInsideRect(DrawRect rect, DrawPoint point) =>
    point.x > rect.minX + _insideEpsilon &&
    point.x < rect.maxX - _insideEpsilon &&
    point.y > rect.minY + _insideEpsilon &&
    point.y < rect.maxY - _insideEpsilon;

DrawPoint? _intersectRectAlongLine({
  required DrawRect rect,
  required DrawPoint reference,
  required DrawPoint target,
  DrawPoint? preferPoint,
  bool preferRay = false,
}) {
  final dx = target.x - reference.x;
  final dy = target.y - reference.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= _intersectionEpsilon) {
    return null;
  }

  final dirX = dx / length;
  final dirY = dy / length;
  final maxDim = math.max(rect.width.abs(), rect.height.abs());
  final extend = length + maxDim + _bindingGapBase * 2;

  final start = DrawPoint(
    x: reference.x - dirX * extend,
    y: reference.y - dirY * extend,
  );
  final end = DrawPoint(
    x: reference.x + dirX * extend,
    y: reference.y + dirY * extend,
  );

  final intersections = _segmentRectIntersections(
    rect: rect,
    start: start,
    end: end,
  );
  if (intersections.isEmpty) {
    return null;
  }

  if (preferRay) {
    DrawPoint? best;
    var bestT = double.infinity;
    for (final intersection in intersections) {
      final t =
          (intersection.x - reference.x) * dirX +
          (intersection.y - reference.y) * dirY;
      if (t < -_intersectionEpsilon) {
        continue;
      }
      if (t < bestT) {
        bestT = t;
        best = intersection;
      }
    }
    if (best != null) {
      return best;
    }
    return null;
  }

  final sortPoint = preferPoint ?? reference;
  intersections.sort(
    (a, b) =>
        sortPoint.distanceSquared(a).compareTo(sortPoint.distanceSquared(b)),
  );
  return intersections.first;
}

List<DrawPoint> _segmentRectIntersections({
  required DrawRect rect,
  required DrawPoint start,
  required DrawPoint end,
}) {
  final intersections = <DrawPoint>[];
  final dx = end.x - start.x;
  final dy = end.y - start.y;

  void addIfValid(double t, double x, double y) {
    if (t < -_intersectionEpsilon || t > 1 + _intersectionEpsilon) {
      return;
    }
    if (x < rect.minX - _intersectionEpsilon ||
        x > rect.maxX + _intersectionEpsilon ||
        y < rect.minY - _intersectionEpsilon ||
        y > rect.maxY + _intersectionEpsilon) {
      return;
    }
    final point = DrawPoint(x: x, y: y);
    for (final existing in intersections) {
      if (existing.distanceSquared(point) <=
          _intersectionEpsilon * _intersectionEpsilon) {
        return;
      }
    }
    intersections.add(point);
  }

  if (dx.abs() > _intersectionEpsilon) {
    var t = (rect.minX - start.x) / dx;
    var y = start.y + t * dy;
    addIfValid(t, rect.minX, y);

    t = (rect.maxX - start.x) / dx;
    y = start.y + t * dy;
    addIfValid(t, rect.maxX, y);
  }

  if (dy.abs() > _intersectionEpsilon) {
    var t = (rect.minY - start.y) / dy;
    var x = start.x + t * dx;
    addIfValid(t, x, rect.minY);

    t = (rect.maxY - start.y) / dy;
    x = start.x + t * dx;
    addIfValid(t, x, rect.maxY);
  }

  return intersections;
}

double _clamp(double value, double min, double max) =>
    math.min(math.max(value, min), max);

double _clamp01(double value) => _clamp(value, 0, 1);
