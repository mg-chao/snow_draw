import 'package:meta/meta.dart';

import '../../../../utils/list_equality.dart';
import 'elbow_fixed_segment.dart';

/// Stores elbow-only routing metadata for an arrow.
///
/// Straight and curved arrows do not need fixed-segment locks or the
/// additional endpoint flags, so this state lives separately from the base
/// arrow payload.
@immutable
final class ElbowRoutingData {
  const ElbowRoutingData({
    this.fixedSegments,
    this.startIsSpecial,
    this.endIsSpecial,
  });

  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;

  bool get isEmpty =>
      (fixedSegments == null || fixedSegments!.isEmpty) &&
      startIsSpecial == null &&
      endIsSpecial == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElbowRoutingData &&
          fixedSegmentListEquals(other.fixedSegments, fixedSegments) &&
          other.startIsSpecial == startIsSpecial &&
          other.endIsSpecial == endIsSpecial;

  @override
  int get hashCode => Object.hash(
    fixedSegments == null ? null : Object.hashAll(fixedSegments!),
    startIsSpecial,
    endIsSpecial,
  );
}
