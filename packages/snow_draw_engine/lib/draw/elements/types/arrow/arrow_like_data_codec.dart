import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
import 'arrow_binding.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';
import 'elbow/elbow_routing_data.dart';

/// Shared serialization helpers for arrow-like data implementations.
final class ArrowLikeDataCodec {
  const ArrowLikeDataCodec._();

  static List<DrawPoint> decodePoints(Object? rawPoints) {
    if (rawPoints is! List) {
      throw const FormatException('Arrow points must be a JSON array');
    }

    final points = <DrawPoint>[
      for (final rawPoint in rawPoints)
        ElementDataCodec.decodePoint(rawPoint, fieldName: 'points entry'),
    ];

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
  }) => _resolveUpdate(
    rawValue: rawBinding,
    currentValue: currentBinding,
    decode: (raw) => raw as ArrowBinding?,
  );

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
  }) => _resolveUpdate(
    rawValue: rawFixedSegments,
    currentValue: currentFixedSegments,
    decode: (raw) => normalizeFixedSegments(raw as List<ElbowFixedSegment>?),
  );

  static bool? resolveNullableBoolUpdate({
    required Object? rawValue,
    required bool? currentValue,
  }) => _resolveUpdate(
    rawValue: rawValue,
    currentValue: currentValue,
    decode: (raw) => raw as bool?,
  );

  static ElbowRoutingData? decodeElbowRoutingData({
    required Object? rawFixedSegments,
    required Object? rawStartIsSpecial,
    required Object? rawEndIsSpecial,
  }) {
    final routingData = ElbowRoutingData(
      fixedSegments: decodeFixedSegments(rawFixedSegments),
      startIsSpecial: ElementDataCodec.decodeNullableBool(
        rawStartIsSpecial,
        fieldName: 'startIsSpecial',
      ),
      endIsSpecial: ElementDataCodec.decodeNullableBool(
        rawEndIsSpecial,
        fieldName: 'endIsSpecial',
      ),
    );
    return routingData.isEmpty ? null : routingData;
  }

  static ElbowRoutingData? resolveElbowRoutingUpdate({
    required Object? rawFixedSegments,
    required Object? rawStartIsSpecial,
    required Object? rawEndIsSpecial,
    required ElbowRoutingData? currentRoutingData,
  }) {
    if (identical(rawFixedSegments, ArrowLikeData.unset) &&
        identical(rawStartIsSpecial, ArrowLikeData.unset) &&
        identical(rawEndIsSpecial, ArrowLikeData.unset)) {
      return currentRoutingData;
    }

    final routingData = ElbowRoutingData(
      fixedSegments: resolveFixedSegmentsUpdate(
        rawFixedSegments: rawFixedSegments,
        currentFixedSegments: currentRoutingData?.fixedSegments,
      ),
      startIsSpecial: resolveNullableBoolUpdate(
        rawValue: rawStartIsSpecial,
        currentValue: currentRoutingData?.startIsSpecial,
      ),
      endIsSpecial: resolveNullableBoolUpdate(
        rawValue: rawEndIsSpecial,
        currentValue: currentRoutingData?.endIsSpecial,
      ),
    );
    return routingData.isEmpty ? null : routingData;
  }

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

  static T _resolveUpdate<T>({
    required Object? rawValue,
    required T currentValue,
    required T Function(Object? raw) decode,
  }) => identical(rawValue, ArrowLikeData.unset)
      ? currentValue
      : decode(rawValue);
}
