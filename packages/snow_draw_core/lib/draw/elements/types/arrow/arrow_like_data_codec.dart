import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
import 'arrow_binding.dart';
import 'elbow/elbow_fixed_segment.dart';

/// Shared serialization helpers for arrow-like data implementations.
final class ArrowLikeDataCodec {
  const ArrowLikeDataCodec._();

  static List<DrawPoint> decodePoints(
    Object? rawPoints, {
    required List<DrawPoint> fallback,
  }) {
    final points = <DrawPoint>[];
    if (rawPoints is List) {
      for (final entry in rawPoints) {
        if (entry is! Map) {
          continue;
        }
        final x = (entry['x'] as num?)?.toDouble();
        final y = (entry['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          points.add(DrawPoint(x: x, y: y));
        }
      }
    }

    if (points.length < 2) {
      return fallback;
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static ArrowBinding? decodeBinding(Object? raw) {
    final map = ElementDataCodec.asJsonMap(raw);
    if (map == null) {
      return null;
    }
    return ArrowBinding.fromJson(map);
  }

  static List<ElbowFixedSegment>? decodeFixedSegments(Object? raw) {
    if (raw is! List) {
      return null;
    }

    final segments = <ElbowFixedSegment>[];
    for (final entry in raw) {
      final map = ElementDataCodec.asJsonMap(entry);
      if (map == null) {
        continue;
      }
      try {
        segments.add(ElbowFixedSegment.fromJson(map));
      } on FormatException {
        // Skip invalid segment entries.
      }
    }

    return normalizeFixedSegments(segments);
  }

  static List<ElbowFixedSegment>? normalizeFixedSegments(
    List<ElbowFixedSegment>? segments,
  ) {
    if (segments == null || segments.isEmpty) {
      return null;
    }
    return List<ElbowFixedSegment>.unmodifiable(segments);
  }
}
