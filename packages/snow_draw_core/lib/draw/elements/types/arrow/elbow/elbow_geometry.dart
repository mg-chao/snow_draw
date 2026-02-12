import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../utils/selection_calculator.dart';
import '../arrow_binding.dart';
import 'elbow_constants.dart';
import 'elbow_heading.dart';

/// Internal axis tagging for elbow paths.
enum ElbowAxis {
  horizontal,
  vertical;

  /// Whether this axis is horizontal.
  bool get isHorizontal => this == ElbowAxis.horizontal;

  /// Whether this axis is vertical.
  bool get isVertical => this == ElbowAxis.vertical;
}

/// Shared geometry helpers for elbow routing and editing.
final class ElbowGeometry {
  const ElbowGeometry._();

  static const _headingEpsilon = 1e-6;

  /// Returns the dominant cardinal heading for a vector.
  ///
  /// The dominant axis wins; ties favor horizontal headings.
  static ElbowHeading headingForVector(double dx, double dy) {
    final absX = dx.abs();
    final absY = dy.abs();
    if (absX >= absY) {
      return dx >= 0 ? ElbowHeading.right : ElbowHeading.left;
    }
    return dy >= 0 ? ElbowHeading.down : ElbowHeading.up;
  }

  /// Returns the heading for a segment from [from] to [to].
  static ElbowHeading headingForSegment(DrawPoint from, DrawPoint to) =>
      headingForVector(to.x - from.x, to.y - from.y);

  /// Manhattan distance between two points.
  static double manhattanDistance(DrawPoint a, DrawPoint b) =>
      (a.x - b.x).abs() + (a.y - b.y).abs();

  /// Returns true when the segment is closer to horizontal than vertical.
  static bool isHorizontal(DrawPoint a, DrawPoint b) =>
      (a.y - b.y).abs() <= (a.x - b.x).abs();

  /// Determines which side of the bounds a point belongs to, using
  /// a scaled-triangle quadrant test around the center.
  static ElbowHeading headingForPointOnBounds(
    DrawRect bounds,
    DrawPoint point,
  ) {
    final center = bounds.center;
    const scale = 2.0;
    final topLeft = _scalePointFromOrigin(
      DrawPoint(x: bounds.minX, y: bounds.minY),
      center,
      scale,
    );
    final topRight = _scalePointFromOrigin(
      DrawPoint(x: bounds.maxX, y: bounds.minY),
      center,
      scale,
    );
    final bottomLeft = _scalePointFromOrigin(
      DrawPoint(x: bounds.minX, y: bounds.maxY),
      center,
      scale,
    );
    final bottomRight = _scalePointFromOrigin(
      DrawPoint(x: bounds.maxX, y: bounds.maxY),
      center,
      scale,
    );

    if (_triangleContainsPoint(topLeft, topRight, center, point)) {
      return ElbowHeading.up;
    }
    if (_triangleContainsPoint(topRight, bottomRight, center, point)) {
      return ElbowHeading.right;
    }
    if (_triangleContainsPoint(bottomRight, bottomLeft, center, point)) {
      return ElbowHeading.down;
    }
    return ElbowHeading.left;
  }

  static DrawPoint _scalePointFromOrigin(
    DrawPoint point,
    DrawPoint origin,
    double scale,
  ) => DrawPoint(
    x: origin.x + (point.x - origin.x) * scale,
    y: origin.y + (point.y - origin.y) * scale,
  );

  static DrawPoint _vectorFromPoints(DrawPoint to, DrawPoint from) =>
      DrawPoint(x: to.x - from.x, y: to.y - from.y);

  static double _dotProduct(DrawPoint a, DrawPoint b) => a.x * b.x + a.y * b.y;

  static bool _triangleContainsPoint(
    DrawPoint a,
    DrawPoint b,
    DrawPoint c,
    DrawPoint point,
  ) {
    final v0 = _vectorFromPoints(c, a);
    final v1 = _vectorFromPoints(b, a);
    final v2 = _vectorFromPoints(point, a);

    final dot00 = _dotProduct(v0, v0);
    final dot01 = _dotProduct(v0, v1);
    final dot02 = _dotProduct(v0, v2);
    final dot11 = _dotProduct(v1, v1);
    final dot12 = _dotProduct(v1, v2);

    final denom = dot00 * dot11 - dot01 * dot01;
    if (denom.abs() <= _headingEpsilon) {
      return false;
    }
    final invDenom = 1 / denom;
    final u = (dot11 * dot02 - dot01 * dot12) * invDenom;
    final v = (dot00 * dot12 - dot01 * dot02) * invDenom;

    return u >= -_headingEpsilon &&
        v >= -_headingEpsilon &&
        u + v <= 1 + _headingEpsilon;
  }

  // --- Methods absorbed from ElbowPathUtils ---

  /// Returns an axis only when the segment is axis-aligned within tolerance.
  static ElbowAxis? axisAlignedForSegment(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    if (dx <= epsilon && dy <= epsilon) {
      return null;
    }
    if (dy <= epsilon) {
      return ElbowAxis.horizontal;
    }
    if (dx <= epsilon) {
      return ElbowAxis.vertical;
    }
    return null;
  }

  /// Returns a stable axis for a segment, falling back to the dominant axis.
  static ElbowAxis axisForSegment(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) {
    final aligned = axisAlignedForSegment(a, b, epsilon: epsilon);
    if (aligned != null) {
      return aligned;
    }
    return isHorizontal(a, b) ? ElbowAxis.horizontal : ElbowAxis.vertical;
  }

  /// Returns true when a segment is (or should be treated as) horizontal.
  static bool segmentIsHorizontal(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) => axisForSegment(a, b, epsilon: epsilon).isHorizontal;

  /// Returns true when a segment is (or should be treated as) vertical.
  static bool segmentIsVertical(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) => axisForSegment(a, b, epsilon: epsilon).isVertical;

  /// Returns the shared axis coordinate for a segment.
  static double axisValue(
    DrawPoint start,
    DrawPoint end, {
    required ElbowAxis axis,
  }) => axis.isHorizontal ? (start.y + end.y) / 2 : (start.x + end.x) / 2;

  /// Returns true when two points are nearly identical.
  static bool pointsClose(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) => (a.x - b.x).abs() <= epsilon && (a.y - b.y).abs() <= epsilon;

  /// Returns true when two points align on either axis.
  static bool pointsAligned(
    DrawPoint a,
    DrawPoint b, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) => (a.x - b.x).abs() <= epsilon || (a.y - b.y).abs() <= epsilon;

  /// Returns true when three points form a straight orthogonal line.
  static bool segmentsCollinear(
    DrawPoint a,
    DrawPoint b,
    DrawPoint c, {
    double epsilon = ElbowConstants.dedupThreshold,
  }) {
    final axis = axisAlignedForSegment(a, b, epsilon: epsilon);
    final nextAxis = axisAlignedForSegment(b, c, epsilon: epsilon);
    if (axis == null || nextAxis == null || axis != nextAxis) {
      return false;
    }
    final axisValueA = axisValue(a, b, axis: axis);
    final axisValueB = axisValue(b, c, axis: axis);
    return (axisValueA - axisValueB).abs() <= epsilon;
  }

  /// Returns a direct elbow path with a single corner when possible.
  static List<DrawPoint> directElbowPath(
    DrawPoint start,
    DrawPoint end, {
    required bool preferHorizontal,
    double epsilon = ElbowConstants.dedupThreshold,
  }) {
    if ((start.x - end.x).abs() <= epsilon ||
        (start.y - end.y).abs() <= epsilon) {
      return [start, end];
    }
    final mid = preferHorizontal
        ? DrawPoint(x: end.x, y: start.y)
        : DrawPoint(x: start.x, y: end.y);
    if (mid == start || mid == end) {
      return [start, end];
    }
    return [start, mid, end];
  }

  /// Removes short interior segments while keeping endpoints intact.
  static List<DrawPoint> removeShortSegments(
    List<DrawPoint> points, {
    double minLength = ElbowConstants.dedupThreshold,
  }) {
    if (points.length < 4) {
      return points;
    }
    return [
      points.first,
      for (var i = 1; i < points.length - 1; i++)
        if (manhattanDistance(points[i - 1], points[i]) > minLength) points[i],
      points.last,
    ];
  }

  /// Keeps only the corner points of an orthogonal polyline.
  static List<DrawPoint> cornerPoints(List<DrawPoint> points) {
    if (points.length <= 2) {
      return points;
    }
    var prevH = segmentIsHorizontal(points[0], points[1]);
    final result = <DrawPoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final nextH = segmentIsHorizontal(points[i], points[i + 1]);
      if (prevH != nextH) {
        result.add(points[i]);
      }
      prevH = nextH;
    }
    result.add(points.last);
    return result;
  }

  /// Simplifies an orthogonal path while keeping pinned points intact.
  static List<DrawPoint> simplifyPath(
    List<DrawPoint> points, {
    Set<DrawPoint> pinned = const <DrawPoint>{},
  }) {
    if (points.length < 3) {
      return points;
    }

    // Remove collinear interior points (keep pinned).
    final reduced = <DrawPoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final p = points[i];
      if (pinned.contains(p) ||
          segmentIsHorizontal(reduced.last, p) !=
              segmentIsHorizontal(p, points[i + 1])) {
        reduced.add(p);
      }
    }
    reduced.add(points.last);

    // Remove near-duplicate consecutive points.
    final cleaned = <DrawPoint>[reduced.first];
    for (var i = 1; i < reduced.length; i++) {
      final p = reduced[i];
      if (p != cleaned.last &&
          (pinned.contains(p) ||
              manhattanDistance(cleaned.last, p) >
                  ElbowConstants.dedupThreshold)) {
        cleaned.add(p);
      }
    }
    return List<DrawPoint>.unmodifiable(cleaned);
  }

  /// Merges consecutive segments that share the same heading.
  ///
  /// Two segments with the same heading (e.g. both Right) but at
  /// different axis values indicate a redundant intermediate point.
  /// Removing it collapses the pair into a single segment.
  /// Pinned points are preserved.
  static List<DrawPoint> mergeConsecutiveSameHeading(
    List<DrawPoint> points, {
    Set<DrawPoint> pinned = const <DrawPoint>{},
  }) {
    if (points.length < 3) {
      return points;
    }
    var changed = true;
    var current = points;
    while (changed) {
      changed = false;
      final result = <DrawPoint>[current.first];
      for (var i = 1; i < current.length - 1; i++) {
        final prev = result.last;
        final mid = current[i];
        final next = current[i + 1];
        final prevLen = manhattanDistance(prev, mid);
        final nextLen = manhattanDistance(mid, next);
        if (prevLen <= ElbowConstants.dedupThreshold ||
            nextLen <= ElbowConstants.dedupThreshold) {
          result.add(mid);
          continue;
        }
        final prevH = headingForSegment(prev, mid);
        final nextH = headingForSegment(mid, next);
        if (prevH == nextH && !pinned.contains(mid)) {
          changed = true;
          continue;
        }
        result.add(mid);
      }
      result.add(current.last);
      current = result;
    }
    return List<DrawPoint>.unmodifiable(current);
  }

  /// Returns true when any segment is diagonal beyond the tolerance.
  static bool hasDiagonalSegments(List<DrawPoint> points) {
    for (var i = 1; i < points.length; i++) {
      if ((points[i].x - points[i - 1].x).abs() >
              ElbowConstants.dedupThreshold &&
          (points[i].y - points[i - 1].y).abs() >
              ElbowConstants.dedupThreshold) {
        return true;
      }
    }
    return false;
  }

  /// Offsets [point] along [heading] by [distance].
  static DrawPoint offsetPoint(
    DrawPoint point,
    ElbowHeading heading,
    double distance,
  ) => DrawPoint(
    x: point.x + heading.dx * distance,
    y: point.y + heading.dy * distance,
  );

  /// Total Manhattan path length across all segments.
  static double pathLength(List<DrawPoint> points) {
    var length = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      length += manhattanDistance(points[i], points[i + 1]);
    }
    return length;
  }

  /// Whether two point lists are element-wise equal.
  static bool pointListsEqual(List<DrawPoint> a, List<DrawPoint> b) {
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

  /// Whether two point lists are equal except at the first and last
  /// positions.
  static bool pointListsEqualExceptEndpoints(
    List<DrawPoint> a,
    List<DrawPoint> b,
  ) {
    if (a.length != b.length || a.length < 2) {
      return false;
    }
    for (var i = 1; i < a.length - 1; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Resolves the bound heading for an arrow endpoint.
  ///
  /// Returns the cardinal direction the arrow should exit from the
  /// bound element, or `null` when the binding target is missing.
  static ElbowHeading? resolveBoundHeading({
    required ArrowBinding binding,
    required Map<String, ElementState> elementsById,
    required DrawPoint point,
  }) {
    final element = elementsById[binding.elementId];
    if (element == null) {
      return null;
    }
    final bounds = SelectionCalculator.computeElementWorldAabb(element);
    final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
      binding: binding,
      target: element,
    );
    return headingForPointOnBounds(bounds, anchor ?? point);
  }
}
