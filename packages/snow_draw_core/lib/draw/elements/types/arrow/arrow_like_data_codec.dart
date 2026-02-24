import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
import 'arrow_binding.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

/// Shared serialization helpers for arrow-like data implementations.
final class ArrowLikeDataCodec {
  const ArrowLikeDataCodec._();

  static List<DrawPoint> decodePoints(Object? rawPoints) {
    if (rawPoints is! List) {
      throw const FormatException('Arrow points must be a JSON array');
    }

    final points = <DrawPoint>[];
    for (final rawPoint in rawPoints) {
      final pointMap = ElementDataCodec.asJsonMap(
        rawPoint,
        fieldName: 'points entry',
      );
      final x = pointMap['x'];
      final y = pointMap['y'];
      if (x is! num || y is! num) {
        throw const FormatException('Arrow points must provide numeric x/y');
      }
      points.add(DrawPoint(x: x.toDouble(), y: y.toDouble()));
    }

    if (points.length < 2) {
      throw const FormatException(
        'Arrow payload must include at least two points',
      );
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static ArrowBinding? decodeBinding(Object? raw) {
    final map = ElementDataCodec.asNullableJsonMap(raw, fieldName: 'binding');
    if (map == null) {
      return null;
    }
    return ArrowBinding.fromJson(map);
  }

  static ArrowBinding? resolveBindingUpdate({
    required Object? rawBinding,
    required ArrowBinding? currentBinding,
  }) => identical(rawBinding, ArrowLikeData.unset)
      ? currentBinding
      : rawBinding as ArrowBinding?;

  static List<ElbowFixedSegment>? decodeFixedSegments(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! List) {
      throw const FormatException('fixedSegments must be a JSON array');
    }

    final segments = <ElbowFixedSegment>[];
    for (final entry in raw) {
      final map = ElementDataCodec.asJsonMap(
        entry,
        fieldName: 'fixedSegments entry',
      );
      segments.add(ElbowFixedSegment.fromJson(map));
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

  static List<ElbowFixedSegment>? resolveFixedSegmentsUpdate({
    required Object? rawFixedSegments,
    required List<ElbowFixedSegment>? currentFixedSegments,
  }) => identical(rawFixedSegments, ArrowLikeData.unset)
      ? currentFixedSegments
      : normalizeFixedSegments(rawFixedSegments as List<ElbowFixedSegment>?);

  static bool? resolveNullableBoolUpdate({
    required Object? rawValue,
    required bool? currentValue,
  }) => identical(rawValue, ArrowLikeData.unset)
      ? currentValue
      : rawValue as bool?;

  static List<Map<String, double>> encodePoints(List<DrawPoint> points) => [
    for (final point in points) {'x': point.x, 'y': point.y},
  ];

  static List<Map<String, dynamic>>? encodeFixedSegments(
    List<ElbowFixedSegment>? segments,
  ) {
    if (segments == null || segments.isEmpty) {
      return null;
    }
    return [for (final segment in segments) segment.toJson()];
  }
}
