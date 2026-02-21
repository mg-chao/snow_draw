import '../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../types/draw_point.dart';
import '../types/edit_transform.dart' show ArrowPointTransform;

/// Shared list-equality helpers used across element data classes and
/// edit operations.
///
/// These replace the many private `_pointsEqual` / `_fixedSegmentsEqual`
/// copies that were scattered throughout the codebase.

/// Element-wise equality for [DrawPoint] lists.
bool pointListEquals(List<DrawPoint> a, List<DrawPoint> b) =>
    _listEquals(a, b, (left, right) => left == right);

/// Element-wise equality for nullable [ElbowFixedSegment] lists.
///
/// Uses strict `!=` comparison (index + start + end), matching the
/// semantics used by data-class `==` operators.
bool fixedSegmentListEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) => _nullableListEquals(a, b, (left, right) => left == right);

/// Whether segment [a] is horizontal based on its endpoints.
bool segmentIsHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

/// Structural equality for [ElbowFixedSegment] lists used by
/// [ArrowPointTransform] - compares index and axis orientation
/// rather than exact start/end positions.
bool fixedSegmentStructureEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) => _nullableListEquals(a, b, _fixedSegmentStructureItemEquals);

/// Structural equality with axis-value tolerance, used by the arrow
/// point operation to detect meaningful segment changes.
bool fixedSegmentStructureEqualsWithTolerance(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b, {
  double tolerance = 1.0,
}) {
  assert(tolerance >= 0, 'tolerance must be non-negative.');
  return _nullableListEquals(
    a,
    b,
    (left, right) =>
        _fixedSegmentStructureItemEquals(left, right, tolerance: tolerance),
  );
}

bool _nullableListEquals<T>(
  List<T>? a,
  List<T>? b,
  bool Function(T left, T right) elementEquals,
) {
  if (a == null || b == null) {
    return a == b;
  }
  return _listEquals(a, b, elementEquals);
}

bool _listEquals<T>(
  List<T> a,
  List<T> b,
  bool Function(T left, T right) elementEquals,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (!elementEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

bool _fixedSegmentStructureItemEquals(
  ElbowFixedSegment a,
  ElbowFixedSegment b, {
  double? tolerance,
}) {
  if (a.index != b.index) {
    return false;
  }

  final isHorizontal = segmentIsHorizontal(a.start, a.end);
  if (isHorizontal != segmentIsHorizontal(b.start, b.end)) {
    return false;
  }

  if (tolerance == null) {
    return true;
  }

  return (_segmentAxis(a, isHorizontal) - _segmentAxis(b, isHorizontal))
          .abs() <=
      tolerance;
}

double _segmentAxis(ElbowFixedSegment segment, bool isHorizontal) {
  if (isHorizontal) {
    return (segment.start.y + segment.end.y) / 2;
  }
  return (segment.start.x + segment.end.x) / 2;
}
