import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';
import 'elbow_fixed_segment.dart';
import 'elbow_router.dart';

const double _dedupThreshold = 1;
const double _minFixedSegmentLength = 40;

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

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) {
  final points = localPointsOverride ?? _resolveLocalPoints(element, data);
  if (points.length < 2) {
    return ElbowEditResult(
      localPoints: points,
      fixedSegments: null,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  final fixedSegments = _sanitizeFixedSegments(
    fixedSegmentsOverride ?? data.fixedSegments,
    points.length,
  );
  final startBinding = startBindingOverride ?? data.startBinding;
  final endBinding = endBindingOverride ?? data.endBinding;

  if (fixedSegments.isEmpty) {
    final routed = routeElbowArrowForElement(
      element: element,
      data: data.copyWith(
        startBinding: startBinding,
        endBinding: endBinding,
      ),
      elementsById: elementsById,
      startOverride: points.first,
      endOverride: points.last,
    );
    return ElbowEditResult(
      localPoints: routed.localPoints,
      fixedSegments: null,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  final built = _buildPathWithFixedSegments(
    element: element,
    data: data,
    elementsById: elementsById,
    startPoint: points.first,
    endPoint: points.last,
    fixedSegments: fixedSegments,
    startBinding: startBinding,
    endBinding: endBinding,
  );
  final simplified = _simplifyPath(
    points: built,
    fixedSegments: fixedSegments,
    startPoint: points.first,
    endPoint: points.last,
  );
  final reindexed = _reindexFixedSegments(simplified, fixedSegments);
  final resultSegments = reindexed.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(reindexed);

  return ElbowEditResult(
    localPoints: simplified,
    fixedSegments: resultSegments,
    startIsSpecial: data.startIsSpecial,
    endIsSpecial: data.endIsSpecial,
  );
}

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

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

List<ElbowFixedSegment> _sanitizeFixedSegments(
  List<ElbowFixedSegment>? segments,
  int pointCount,
) {
  if (segments == null || segments.isEmpty || pointCount < 2) {
    return const [];
  }
  final maxIndex = pointCount - 1;
  final result = <ElbowFixedSegment>[];
  for (final segment in segments) {
    if (segment.index <= 1 || segment.index >= maxIndex) {
      continue;
    }
    if (segment.index < 1 || segment.index >= pointCount) {
      continue;
    }
    final dx = (segment.start.x - segment.end.x).abs();
    final dy = (segment.start.y - segment.end.y).abs();
    if (dx > _dedupThreshold && dy > _dedupThreshold) {
      continue;
    }
    final length = _manhattanDistance(segment.start, segment.end);
    if (length < _minFixedSegmentLength) {
      continue;
    }
    if (result.any((entry) => entry.index == segment.index)) {
      continue;
    }
    result.add(segment);
  }
  result.sort((a, b) => a.index.compareTo(b.index));
  return result;
}

List<DrawPoint> _buildPathWithFixedSegments({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required List<ElbowFixedSegment> fixedSegments,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final orderedSegments = [...fixedSegments]
    ..sort((a, b) => a.index.compareTo(b.index));
  final points = <DrawPoint>[];
  var currentStart = startPoint;

  for (var i = 0; i < orderedSegments.length; i++) {
    final segment = orderedSegments[i];
    final routed = _routeLocalPath(
      element: element,
      data: data,
      elementsById: elementsById,
      startLocal: currentStart,
      endLocal: segment.start,
      startBinding: i == 0 ? startBinding : null,
      endBinding: null,
      startArrowhead: i == 0 ? data.startArrowhead : ArrowheadStyle.none,
      endArrowhead: ArrowheadStyle.none,
    );
    _appendPath(points, routed);

    if (points.isEmpty || points.last != segment.start) {
      points.add(segment.start);
    }
    if (points.isEmpty || points.last != segment.end) {
      points.add(segment.end);
    }
    currentStart = segment.end;
  }

  final tail = _routeLocalPath(
    element: element,
    data: data,
    elementsById: elementsById,
    startLocal: currentStart,
    endLocal: endPoint,
    startBinding: orderedSegments.isEmpty ? startBinding : null,
    endBinding: endBinding,
    startArrowhead:
        orderedSegments.isEmpty ? data.startArrowhead : ArrowheadStyle.none,
    endArrowhead: data.endArrowhead,
  );
  _appendPath(points, tail);

  return points;
}

List<DrawPoint> _routeLocalPath({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  required DrawPoint startLocal,
  required DrawPoint endLocal,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final space = ElementSpace(rotation: element.rotation, origin: element.rect.center);
  final worldStart = space.toWorld(startLocal);
  final worldEnd = space.toWorld(endLocal);
  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: elementsById,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  return routed.points
      .map(space.fromWorld)
      .toList(growable: false);
}

void _appendPath(List<DrawPoint> target, List<DrawPoint> path) {
  if (path.isEmpty) {
    return;
  }
  if (target.isEmpty) {
    target.addAll(path);
    return;
  }
  if (target.last == path.first) {
    target.addAll(path.skip(1));
  } else {
    target.addAll(path);
  }
}

List<DrawPoint> _simplifyPath({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
}) {
  if (points.length < 3) {
    return points;
  }

  final pinned = <DrawPoint>{
    startPoint,
    endPoint,
    for (final segment in fixedSegments) segment.start,
    for (final segment in fixedSegments) segment.end,
  };

  final withoutCollinear = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final point = points[i];
    if (pinned.contains(point)) {
      withoutCollinear.add(point);
      continue;
    }
    final prev = withoutCollinear.last;
    final next = points[i + 1];
    final isHorizontalPrev = _isHorizontal(prev, point);
    final isHorizontalNext = _isHorizontal(point, next);
    if (isHorizontalPrev == isHorizontalNext) {
      continue;
    }
    withoutCollinear.add(point);
  }
  withoutCollinear.add(points.last);

  final cleaned = <DrawPoint>[withoutCollinear.first];
  for (var i = 1; i < withoutCollinear.length; i++) {
    final point = withoutCollinear[i];
    if (point == cleaned.last) {
      continue;
    }
    final length = _manhattanDistance(cleaned.last, point);
    if (length <= _dedupThreshold && !pinned.contains(point)) {
      continue;
    }
    cleaned.add(point);
  }

  return List<DrawPoint>.unmodifiable(cleaned);
}

List<ElbowFixedSegment> _reindexFixedSegments(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (fixedSegments.isEmpty || points.length < 2) {
    return const [];
  }
  final maxIndex = points.length - 1;
  final result = <ElbowFixedSegment>[];
  for (final segment in fixedSegments) {
    final index = _findSegmentIndex(points, segment.start, segment.end);
    if (index == null || index <= 1 || index >= maxIndex) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    final length = _manhattanDistance(start, end);
    if (length < _minFixedSegmentLength) {
      continue;
    }
    result.add(
      segment.copyWith(
        index: index,
        start: start,
        end: end,
      ),
    );
  }
  return result;
}

int? _findSegmentIndex(
  List<DrawPoint> points,
  DrawPoint start,
  DrawPoint end,
) {
  for (var i = 1; i < points.length; i++) {
    if (points[i - 1] == start && points[i] == end) {
      return i;
    }
  }
  return null;
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();
