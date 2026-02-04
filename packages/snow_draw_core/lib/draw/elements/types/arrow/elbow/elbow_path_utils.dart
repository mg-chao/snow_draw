import '../../../../types/draw_point.dart';
import 'elbow_constants.dart';
import 'elbow_geometry.dart';

/// Internal axis tagging for elbow paths.
enum ElbowAxis {
  horizontal,
  vertical;

  bool get isHorizontal => this == ElbowAxis.horizontal;
  bool get isVertical => this == ElbowAxis.vertical;
}

/// Shared, internal helpers for elbow path routing + editing.
///
/// Centralizes alignment/collinearity definitions so edits and routing stay in
/// sync after multiple iterations.
final class ElbowPathUtils {
  const ElbowPathUtils._();

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
    return ElbowGeometry.isHorizontal(a, b)
        ? ElbowAxis.horizontal
        : ElbowAxis.vertical;
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
  }) {
    if ((start.x - end.x).abs() <= ElbowConstants.dedupThreshold ||
        (start.y - end.y).abs() <= ElbowConstants.dedupThreshold) {
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
    final filtered = <DrawPoint>[];
    for (var i = 0; i < points.length; i++) {
      if (i == 0 || i == points.length - 1) {
        filtered.add(points[i]);
        continue;
      }
      if (ElbowGeometry.manhattanDistance(points[i - 1], points[i]) >
          minLength) {
        filtered.add(points[i]);
      }
    }
    return filtered;
  }

  /// Keeps only the corner points of an orthogonal polyline.
  static List<DrawPoint> cornerPoints(List<DrawPoint> points) {
    if (points.length <= 2) {
      return points;
    }

    var previousIsHorizontal = ElbowPathUtils.segmentIsHorizontal(
      points[0],
      points[1],
    );
    final result = <DrawPoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final nextIsHorizontal = ElbowPathUtils.segmentIsHorizontal(
        points[i],
        points[i + 1],
      );
      if (previousIsHorizontal != nextIsHorizontal) {
        result.add(points[i]);
      }
      previousIsHorizontal = nextIsHorizontal;
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

    final withoutCollinear = <DrawPoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final point = points[i];
      if (pinned.contains(point)) {
        withoutCollinear.add(point);
        continue;
      }
      final prev = withoutCollinear.last;
      final next = points[i + 1];
      final isHorizontalPrev = ElbowPathUtils.segmentIsHorizontal(prev, point);
      final isHorizontalNext = ElbowPathUtils.segmentIsHorizontal(point, next);
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
      final length = ElbowGeometry.manhattanDistance(cleaned.last, point);
      if (length <= ElbowConstants.dedupThreshold && !pinned.contains(point)) {
        continue;
      }
      cleaned.add(point);
    }

    return List<DrawPoint>.unmodifiable(cleaned);
  }

  /// Returns true when any segment is diagonal beyond the tolerance.
  static bool hasDiagonalSegments(List<DrawPoint> points) {
    if (points.length < 2) {
      return false;
    }
    for (var i = 1; i < points.length; i++) {
      final dx = (points[i].x - points[i - 1].x).abs();
      final dy = (points[i].y - points[i - 1].y).abs();
      if (dx > ElbowConstants.dedupThreshold &&
          dy > ElbowConstants.dedupThreshold) {
        return true;
      }
    }
    return false;
  }
}
