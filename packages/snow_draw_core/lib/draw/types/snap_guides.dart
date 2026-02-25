import 'package:meta/meta.dart';

import '../utils/list_equality.dart';
import 'draw_point.dart';

enum SnapGuideKind { point, gap }

enum SnapGuideAxis { horizontal, vertical }

/// Visual guide information for snapping.
@immutable
class SnapGuide {
  const SnapGuide({
    required this.kind,
    required this.axis,
    required this.start,
    required this.end,
    this.markers = const [],
    this.label,
  });
  final SnapGuideKind kind;
  final SnapGuideAxis axis;
  final DrawPoint start;
  final DrawPoint end;
  final List<DrawPoint> markers;
  final double? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapGuide &&
          other.kind == kind &&
          other.axis == axis &&
          other.start == start &&
          other.end == end &&
          pointListEquals(other.markers, markers) &&
          other.label == label;

  @override
  int get hashCode =>
      Object.hash(kind, axis, start, end, Object.hashAll(markers), label);
}

/// Element-wise equality for [SnapGuide] lists.
bool snapGuideListEquals(List<SnapGuide> a, List<SnapGuide> b) =>
    listEquals(a, b);
