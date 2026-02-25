import 'package:meta/meta.dart';

import '../../../../types/draw_point.dart';
import 'elbow_constants.dart';
import 'elbow_geometry.dart';

/// A fixed (pinned) segment of an elbow path whose direction and axis are
/// preserved.
///
/// [index] refers to the segment end point in the path list
/// (segment spans points[index - 1] -> points[index]).
@immutable
final class ElbowFixedSegment {
  const ElbowFixedSegment({
    required this.index,
    required this.start,
    required this.end,
  });

  factory ElbowFixedSegment.fromJson(Map<String, dynamic> json) {
    final index = json['index'];
    final start = _decodePoint(json['start']);
    final end = _decodePoint(json['end']);
    if (index is! num || start == null || end == null) {
      throw const FormatException('Invalid ElbowFixedSegment payload');
    }
    return ElbowFixedSegment(index: index.toInt(), start: start, end: end);
  }

  final int index;
  final DrawPoint start;
  final DrawPoint end;

  /// The [ElbowAxis] of this segment.
  ElbowAxis get axis => ElbowGeometry.axisForSegment(start, end);

  /// Whether this segment runs horizontally.
  bool get isHorizontal => axis.isHorizontal;

  /// The shared coordinate along the perpendicular axis.
  ///
  /// For a horizontal segment this is the Y midpoint; for vertical, the X.
  double get axisValue => ElbowGeometry.axisValue(start, end, axis: axis);

  /// Manhattan length of this segment.
  double get length => ElbowGeometry.manhattanDistance(start, end);

  /// Whether this segment has meaningful length.
  bool get isSignificant => length > ElbowConstants.dedupThreshold;

  ElbowFixedSegment copyWith({int? index, DrawPoint? start, DrawPoint? end}) =>
      ElbowFixedSegment(
        index: index ?? this.index,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  Map<String, dynamic> toJson() => {
    'index': index,
    'start': {'x': start.x, 'y': start.y},
    'end': {'x': end.x, 'y': end.y},
  };

  static DrawPoint? _decodePoint(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final x = raw['x'];
    final y = raw['y'];
    if (x is! num || y is! num) {
      return null;
    }

    return DrawPoint(x: x.toDouble(), y: y.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElbowFixedSegment &&
          other.index == index &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(index, start, end);

  @override
  String toString() =>
      'ElbowFixedSegment(index: $index, start: $start, end: $end)';
}
