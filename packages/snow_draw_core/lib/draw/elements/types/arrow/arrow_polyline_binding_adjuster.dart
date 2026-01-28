import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../rectangle/rectangle_data.dart';
import 'arrow_binding.dart';

const double _edgeEpsilon = 1e-3;
const double _axisEpsilon = 1e-3;
const double _bindingGapBase = 6.0;
const double _minApproachOffset = 12.0;

enum _BindingEdge { top, right, bottom, left }

enum _Axis { horizontal, vertical }

List<DrawPoint> adjustPolylinePointsForBinding({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required ElementState target,
  required bool isStart,
}) {
  if (points.length < 2 || binding.mode != ArrowBindingMode.orbit) {
    return points;
  }

  final rect = target.rect;
  if (rect.width == 0 || rect.height == 0) {
    return points;
  }

  final working = isStart
      ? points.reversed.toList(growable: false)
      : List<DrawPoint>.from(points);
  if (working.length < 2) {
    return points;
  }

  final reference = working[working.length - 2];
  final edge = _resolveBindingEdge(binding, rect, reference);
  if (edge == null) {
    return points;
  }

  final adjusted = _adjustPolylineEnd(
    points: working,
    rect: rect,
    edge: edge,
    approachOffset: _resolveApproachOffset(target),
  );

  return isStart
      ? adjusted.reversed.toList(growable: false)
      : adjusted;
}

_BindingEdge? _resolveBindingEdge(
  ArrowBinding binding,
  DrawRect rect,
  DrawPoint reference,
) {
  final nearLeft = binding.anchor.x <= _edgeEpsilon;
  final nearRight = binding.anchor.x >= 1 - _edgeEpsilon;
  final nearTop = binding.anchor.y <= _edgeEpsilon;
  final nearBottom = binding.anchor.y >= 1 - _edgeEpsilon;

  if (nearLeft && !nearTop && !nearBottom) {
    return _BindingEdge.left;
  }
  if (nearRight && !nearTop && !nearBottom) {
    return _BindingEdge.right;
  }
  if (nearTop && !nearLeft && !nearRight) {
    return _BindingEdge.top;
  }
  if (nearBottom && !nearLeft && !nearRight) {
    return _BindingEdge.bottom;
  }

  if ((nearLeft || nearRight) && (nearTop || nearBottom)) {
    final dx = reference.x - rect.centerX;
    final dy = reference.y - rect.centerY;
    final horizontalDominant = dx.abs() >= dy.abs();
    if (nearLeft && nearTop) {
      return horizontalDominant ? _BindingEdge.left : _BindingEdge.top;
    }
    if (nearRight && nearTop) {
      return horizontalDominant ? _BindingEdge.right : _BindingEdge.top;
    }
    if (nearLeft && nearBottom) {
      return horizontalDominant ? _BindingEdge.left : _BindingEdge.bottom;
    }
    if (nearRight && nearBottom) {
      return horizontalDominant ? _BindingEdge.right : _BindingEdge.bottom;
    }
  }

  return null;
}

List<DrawPoint> _adjustPolylineEnd({
  required List<DrawPoint> points,
  required DrawRect rect,
  required _BindingEdge edge,
  required double approachOffset,
}) {
  if (points.length < 2) {
    return points;
  }

  final end = points.last;
  final immediateNeighbor = points[points.length - 2];
  if (_segmentMatchesEdge(edge, immediateNeighbor, end)) {
    return points;
  }

  // Skip points that are inside the bound rect to avoid extra detours.
  var neighborIndex = points.length - 2;
  while (neighborIndex > 0 &&
      _isPointInsideRect(points[neighborIndex], rect)) {
    neighborIndex--;
  }
  final neighbor = points[neighborIndex];

  final approach = _offsetForEdge(end, edge, approachOffset);
  final preferredFirstAxis = _preferredAxisForEdge(edge);
  final path = _buildOrthogonalPath(
    start: neighbor,
    end: approach,
    obstacle: rect,
    detourOffset: approachOffset,
    edge: edge,
    preferredFirstAxis: preferredFirstAxis,
  );

  final updated = <DrawPoint>[
    ...points.sublist(0, neighborIndex + 1),
    ...path.skip(1),
    end,
  ];
  return _simplifyPoints(updated);
}

bool _segmentMatchesEdge(_BindingEdge edge, DrawPoint start, DrawPoint end) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final isHorizontal = dy.abs() <= _axisEpsilon;
  final isVertical = dx.abs() <= _axisEpsilon;

  return switch (edge) {
    _BindingEdge.left => isHorizontal && dx > _axisEpsilon,
    _BindingEdge.right => isHorizontal && dx < -_axisEpsilon,
    _BindingEdge.top => isVertical && dy > _axisEpsilon,
    _BindingEdge.bottom => isVertical && dy < -_axisEpsilon,
  };
}

DrawPoint _offsetForEdge(DrawPoint point, _BindingEdge edge, double offset) =>
    switch (edge) {
      _BindingEdge.left => DrawPoint(x: point.x - offset, y: point.y),
      _BindingEdge.right => DrawPoint(x: point.x + offset, y: point.y),
      _BindingEdge.top => DrawPoint(x: point.x, y: point.y - offset),
      _BindingEdge.bottom => DrawPoint(x: point.x, y: point.y + offset),
    };

List<DrawPoint> _buildOrthogonalPath({
  required DrawPoint start,
  required DrawPoint end,
  required DrawRect obstacle,
  required double detourOffset,
  required _BindingEdge edge,
  _Axis? preferredFirstAxis,
}) {
  if (_isAxisAligned(start, end) &&
      !_segmentIntersectsRect(start, end, obstacle)) {
    return [start, end];
  }

  final horizontalMid = DrawPoint(x: end.x, y: start.y);
  final horizontalPath = [start, horizontalMid, end];
  final verticalMid = DrawPoint(x: start.x, y: end.y);
  final verticalPath = [start, verticalMid, end];

  final horizontalClear = !_pathIntersectsRect(horizontalPath, obstacle);
  final verticalClear = !_pathIntersectsRect(verticalPath, obstacle);

  if (horizontalClear && verticalClear) {
    if (preferredFirstAxis == _Axis.horizontal) {
      return horizontalPath;
    }
    if (preferredFirstAxis == _Axis.vertical) {
      return verticalPath;
    }
    return _pathLength(horizontalPath) <= _pathLength(verticalPath)
        ? horizontalPath
        : verticalPath;
  }

  if (horizontalClear) {
    return horizontalPath;
  }
  if (verticalClear) {
    return verticalPath;
  }

  if (edge == _BindingEdge.top || edge == _BindingEdge.bottom) {
    final detourY = _resolveDetourY(start, obstacle, detourOffset);
    // Favor the bound edge side when detouring to keep the approach perpendicular.
    final outsideX = _resolveDetourX(end, obstacle, detourOffset);
    return [
      start,
      DrawPoint(x: start.x, y: detourY),
      DrawPoint(x: outsideX, y: detourY),
      DrawPoint(x: outsideX, y: end.y),
      end,
    ];
  }

  final outsideY = _resolveDetourY(start, obstacle, detourOffset);
  return [
    start,
    DrawPoint(x: start.x, y: outsideY),
    DrawPoint(x: end.x, y: outsideY),
    end,
  ];
}

bool _isAxisAligned(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() <= _axisEpsilon || (a.y - b.y).abs() <= _axisEpsilon;

_Axis _preferredAxisForEdge(_BindingEdge edge) =>
    (edge == _BindingEdge.left || edge == _BindingEdge.right)
        ? _Axis.horizontal
        : _Axis.vertical;

bool _pathIntersectsRect(List<DrawPoint> path, DrawRect rect) {
  for (var i = 0; i < path.length - 1; i++) {
    if (_segmentIntersectsRect(path[i], path[i + 1], rect)) {
      return true;
    }
  }
  return false;
}

bool _segmentIntersectsRect(DrawPoint a, DrawPoint b, DrawRect rect) {
  if ((a.x - b.x).abs() <= _axisEpsilon) {
    final x = a.x;
    if (x < rect.minX - _axisEpsilon || x > rect.maxX + _axisEpsilon) {
      return false;
    }
    final minY = math.min(a.y, b.y);
    final maxY = math.max(a.y, b.y);
    return maxY >= rect.minY - _axisEpsilon &&
        minY <= rect.maxY + _axisEpsilon;
  }

  if ((a.y - b.y).abs() <= _axisEpsilon) {
    final y = a.y;
    if (y < rect.minY - _axisEpsilon || y > rect.maxY + _axisEpsilon) {
      return false;
    }
    final minX = math.min(a.x, b.x);
    final maxX = math.max(a.x, b.x);
    return maxX >= rect.minX - _axisEpsilon &&
        minX <= rect.maxX + _axisEpsilon;
  }

  return true;
}

bool _isPointInsideRect(DrawPoint point, DrawRect rect) =>
    point.x > rect.minX + _axisEpsilon &&
    point.x < rect.maxX - _axisEpsilon &&
    point.y > rect.minY + _axisEpsilon &&
    point.y < rect.maxY - _axisEpsilon;

double _pathLength(List<DrawPoint> path) {
  var length = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    length += path[i].distance(path[i + 1]);
  }
  return length;
}

double _resolveDetourX(DrawPoint reference, DrawRect rect, double offset) =>
    reference.x >= rect.centerX ? rect.maxX + offset : rect.minX - offset;

double _resolveDetourY(DrawPoint start, DrawRect rect, double offset) =>
    start.y >= rect.centerY ? rect.maxY + offset : rect.minY - offset;

double _resolveApproachOffset(ElementState target) {
  final data = target.data;
  final strokeWidth = data is RectangleData ? data.strokeWidth : 0.0;
  final gap = _bindingGapBase + strokeWidth / 2;
  return math.max(_minApproachOffset, gap * 2);
}

List<DrawPoint> _simplifyPoints(List<DrawPoint> points) {
  if (points.length < 2) {
    return points;
  }

  final deduped = <DrawPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final point = points[i];
    if ((point.x - deduped.last.x).abs() <= _axisEpsilon &&
        (point.y - deduped.last.y).abs() <= _axisEpsilon) {
      continue;
    }
    deduped.add(point);
  }

  if (deduped.length <= 2) {
    return deduped;
  }

  final simplified = <DrawPoint>[deduped.first];
  for (var i = 1; i < deduped.length - 1; i++) {
    final prev = simplified.last;
    final current = deduped[i];
    final next = deduped[i + 1];
    final collinearX =
        (prev.x - current.x).abs() <= _axisEpsilon &&
        (current.x - next.x).abs() <= _axisEpsilon;
    if (collinearX) {
      final minX = math.min(prev.x, next.x);
      final maxX = math.max(prev.x, next.x);
      if (current.x >= minX - _axisEpsilon &&
          current.x <= maxX + _axisEpsilon) {
        continue;
      }
    }

    final collinearY =
        (prev.y - current.y).abs() <= _axisEpsilon &&
        (current.y - next.y).abs() <= _axisEpsilon;
    if (collinearY) {
      final minY = math.min(prev.y, next.y);
      final maxY = math.max(prev.y, next.y);
      if (current.y >= minY - _axisEpsilon &&
          current.y <= maxY + _axisEpsilon) {
        continue;
      }
    }
    simplified.add(current);
  }
  simplified.add(deduped.last);
  return simplified;
}
