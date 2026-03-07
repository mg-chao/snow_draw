import '../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../types/draw_point.dart';

/// Shared list-equality helpers used across element data classes and
/// edit operations.
///
/// These replace the many private `_pointsEqual` / `_fixedSegmentsEqual`
/// copies that were scattered throughout the codebase.

/// Element-wise equality for lists using [elementEquals].
bool listEqualsBy<T>(
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

/// Element-wise equality for lists using `==` comparison.
bool listEquals<T>(List<T> a, List<T> b) =>
    listEqualsBy(a, b, (left, right) => left == right);

/// Hash for a list using positional `Object.hashAll` semantics.
int listHash<T>(List<T> values) => Object.hashAll(values);

/// Nullable variant of [listEqualsBy].
bool nullableListEqualsBy<T>(
  List<T>? a,
  List<T>? b,
  bool Function(T left, T right) elementEquals,
) {
  if (a == null || b == null) {
    return a == b;
  }
  return listEqualsBy(a, b, elementEquals);
}

/// Nullable variant of [listEquals].
bool nullableListEquals<T>(List<T>? a, List<T>? b) =>
    nullableListEqualsBy(a, b, (left, right) => left == right);

/// Hash for a map using deterministic key order.
///
/// Keys are sorted by `toString()` to keep hash generation stable across runs.
int mapHash<K, V>(Map<K, V> map) {
  if (map.isEmpty) {
    return 0;
  }
  final sortedEntries = map.entries.toList(
    growable: false,
  )..sort((left, right) => left.key.toString().compareTo(right.key.toString()));
  return Object.hashAll(
    sortedEntries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// Element-wise equality for maps using key/value equality.
bool mapEqualsBy<K, V>(
  Map<K, V> a,
  Map<K, V> b,
  bool Function(V left, V right) valueEquals,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) {
      return false;
    }
    if (!valueEquals(entry.value, b[entry.key] as V)) {
      return false;
    }
  }
  return true;
}

/// Element-wise equality for maps using `==` for values.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) =>
    mapEqualsBy(a, b, (left, right) => left == right);

/// Element-wise equality for [DrawPoint] lists.
bool pointListEquals(List<DrawPoint> a, List<DrawPoint> b) => listEquals(a, b);

/// Element-wise equality for nullable [ElbowFixedSegment] lists.
///
/// Uses strict `!=` comparison (index + start + end), matching the
/// semantics used by data-class `==` operators.
bool fixedSegmentListEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) => nullableListEquals(a, b);

/// Whether segment [a] is horizontal based on its endpoints.
bool segmentIsHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

/// Structural equality for [ElbowFixedSegment] lists used by
/// arrow point transforms - compares index and axis orientation
/// rather than exact start/end positions.
bool fixedSegmentStructureEquals(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) => nullableListEqualsBy(a, b, _fixedSegmentStructureItemEquals);

/// Structural equality with axis-value tolerance, used by the arrow
/// point operation to detect meaningful segment changes.
bool fixedSegmentStructureEqualsWithTolerance(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b, {
  double tolerance = 1.0,
}) {
  assert(tolerance >= 0, 'tolerance must be non-negative.');
  return nullableListEqualsBy(
    a,
    b,
    (left, right) =>
        _fixedSegmentStructureItemEquals(left, right, tolerance: tolerance),
  );
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
