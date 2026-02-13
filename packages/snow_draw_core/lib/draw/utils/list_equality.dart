import '../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../types/draw_point.dart';

/// Shared list-equality helpers used across element data classes and
/// edit operations.
///
/// These replace the many private `_pointsEqual` / `_fixedSegmentsEqual`
/// copies that were scattered throughout the codebase.

/// Element-wise equality for [DrawPoint] lists.
bool pointListEquals(List<DrawPoint> a, List<DrawPoint> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Element-wise equality for nullable [ElbowFixedSegment] lists.
///
/// Uses strict `!=` comparison (index + start + end), matching the
/// semantics used by data-class `==` operators.
bool fixedSegmentListEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether segment [a] is horizontal based on its endpoints.
bool segmentIsHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

/// Structural equality for [ElbowFixedSegment] lists used by
/// [ArrowPointTransform] — compares index and axis orientation
/// rather than exact start/end positions.
bool fixedSegmentStructureEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) return false;
    if (segmentIsHorizontal(a[i].start, a[i].end) !=
        segmentIsHorizontal(b[i].start, b[i].end)) {
      return false;
    }
  }
  return true;
}

/// Structural equality with axis-value tolerance, used by the arrow
/// point operation to detect meaningful segment changes.
bool fixedSegmentStructureEqualsWithTolerance(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b, {
  double tolerance = 1.0,
}) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) return false;
    final aH = segmentIsHorizontal(a[i].start, a[i].end);
    final bH = segmentIsHorizontal(b[i].start, b[i].end);
    if (aH != bH) return false;
    final aAxis = aH
        ? (a[i].start.y + a[i].end.y) / 2
        : (a[i].start.x + a[i].end.x) / 2;
    final bAxis = bH
        ? (b[i].start.y + b[i].end.y) / 2
        : (b[i].start.x + b[i].end.x) / 2;
    if ((aAxis - bAxis).abs() > tolerance) return false;
  }
  return true;
}
