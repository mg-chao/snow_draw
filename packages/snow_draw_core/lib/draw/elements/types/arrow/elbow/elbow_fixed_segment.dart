import 'package:meta/meta.dart';

import '../../../../types/draw_point.dart';

/// A fixed (pinned) segment of an elbow path.
///
/// [index] points to the segment's start point in the path list.
@immutable
final class ElbowFixedSegment {
  const ElbowFixedSegment({
    required this.index,
    required this.start,
    required this.end,
  });

  factory ElbowFixedSegment.fromJson(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt();
    final start = _decodePoint(json['start']);
    final end = _decodePoint(json['end']);
    if (index == null || start == null || end == null) {
      throw const FormatException('Invalid ElbowFixedSegment payload');
    }
    return ElbowFixedSegment(index: index, start: start, end: end);
  }

  final int index;
  final DrawPoint start;
  final DrawPoint end;

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
    if (raw is Map) {
      final x = (raw['x'] as num?)?.toDouble();
      final y = (raw['y'] as num?)?.toDouble();
      if (x != null && y != null) {
        return DrawPoint(x: x, y: y);
      }
    }
    return null;
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
