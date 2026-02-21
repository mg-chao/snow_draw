import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_color.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/list_equality.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';
import 'arrow_binding.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

@immutable
final class ArrowData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData
    implements ArrowLikeData {
  static const _unset = Object();
  static const List<DrawPoint> _defaultPoints = [
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  const ArrowData({
    this.points = _defaultPoints,
    this.color = ConfigDefaults.defaultColor,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
    this.arrowType = ConfigDefaults.defaultArrowType,
    this.startArrowhead = ConfigDefaults.defaultStartArrowhead,
    this.endArrowhead = ConfigDefaults.defaultEndArrowhead,
    this.startBinding,
    this.endBinding,
    this.fixedSegments,
    this.startIsSpecial,
    this.endIsSpecial,
  });

  factory ArrowData.fromJson(Map<String, dynamic> json) => ArrowData(
    points: _decodePoints(json['points']),
    color: DrawColor(
      (json['color'] as int?) ?? ConfigDefaults.defaultColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultStrokeWidth,
    strokeStyle: _decodeEnum(
      values: StrokeStyle.values,
      raw: json['strokeStyle'],
      fallback: ConfigDefaults.defaultStrokeStyle,
    ),
    arrowType: _decodeEnum(
      values: ArrowType.values,
      raw: json['arrowType'],
      fallback: ConfigDefaults.defaultArrowType,
    ),
    startArrowhead: _decodeEnum(
      values: ArrowheadStyle.values,
      raw: json['startArrowhead'],
      fallback: ConfigDefaults.defaultStartArrowhead,
    ),
    endArrowhead: _decodeEnum(
      values: ArrowheadStyle.values,
      raw: json['endArrowhead'],
      fallback: ConfigDefaults.defaultEndArrowhead,
    ),
    startBinding: _decodeBinding(json['startBinding']),
    endBinding: _decodeBinding(json['endBinding']),
    fixedSegments: _decodeFixedSegments(json['fixedSegments']),
    startIsSpecial: json['startIsSpecial'] as bool?,
    endIsSpecial: json['endIsSpecial'] as bool?,
  );

  static const typeIdToken = ElementTypeId<ArrowData>('arrow');

  /// Normalized control points in element-local space (0..1).
  @override
  final List<DrawPoint> points;
  final DrawColor color;
  @override
  final double strokeWidth;
  @override
  final StrokeStyle strokeStyle;
  @override
  final ArrowType arrowType;
  @override
  final ArrowheadStyle startArrowhead;
  @override
  final ArrowheadStyle endArrowhead;
  @override
  final ArrowBinding? startBinding;
  @override
  final ArrowBinding? endBinding;
  @override
  final List<ElbowFixedSegment>? fixedSegments;
  @override
  final bool? startIsSpecial;
  @override
  final bool? endIsSpecial;

  @override
  ElementTypeId<ArrowData> get typeId => ArrowData.typeIdToken;

  @override
  ArrowData copyWith({
    List<DrawPoint>? points,
    DrawColor? color,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    Object? startBinding = _unset,
    Object? endBinding = _unset,
    Object? fixedSegments = _unset,
    Object? startIsSpecial = _unset,
    Object? endIsSpecial = _unset,
  }) => ArrowData(
    points: points == null ? this.points : List<DrawPoint>.unmodifiable(points),
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    arrowType: arrowType ?? this.arrowType,
    startArrowhead: startArrowhead ?? this.startArrowhead,
    endArrowhead: endArrowhead ?? this.endArrowhead,
    startBinding: identical(startBinding, _unset)
        ? this.startBinding
        : startBinding as ArrowBinding?,
    endBinding: identical(endBinding, _unset)
        ? this.endBinding
        : endBinding as ArrowBinding?,
    fixedSegments: identical(fixedSegments, _unset)
        ? this.fixedSegments
        : _normalizeFixedSegments(fixedSegments as List<ElbowFixedSegment>?),
    startIsSpecial: identical(startIsSpecial, _unset)
        ? this.startIsSpecial
        : startIsSpecial as bool?,
    endIsSpecial: identical(endIsSpecial, _unset)
        ? this.endIsSpecial
        : endIsSpecial as bool?,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
    arrowType: style.arrowType,
    startArrowhead: style.startArrowhead,
    endArrowhead: style.endArrowhead,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: _resolveColor(update.color, color),
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
    arrowType: update.arrowType ?? arrowType,
    startArrowhead: update.startArrowhead ?? startArrowhead,
    endArrowhead: update.endArrowhead ?? endArrowhead,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'points': points.map((point) => {'x': point.x, 'y': point.y}).toList(),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'arrowType': arrowType.name,
    'startArrowhead': startArrowhead.name,
    'endArrowhead': endArrowhead.name,
    'startBinding': startBinding?.toJson(),
    'endBinding': endBinding?.toJson(),
    'fixedSegments': fixedSegments?.map((segment) => segment.toJson()).toList(),
    'startIsSpecial': startIsSpecial,
    'endIsSpecial': endIsSpecial,
  };

  static List<DrawPoint> _decodePoints(Object? rawPoints) {
    final points = <DrawPoint>[];
    if (rawPoints is List) {
      for (final entry in rawPoints) {
        if (entry is Map) {
          final x = (entry['x'] as num?)?.toDouble();
          final y = (entry['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            points.add(DrawPoint(x: x, y: y));
          }
        }
      }
    }

    if (points.length < 2) {
      return _defaultPoints;
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static T _decodeEnum<T extends Enum>({
    required List<T> values,
    required Object? raw,
    required T fallback,
  }) {
    if (raw is! String) {
      return fallback;
    }
    return values.firstWhere(
      (value) => value.name == raw,
      orElse: () => fallback,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowData &&
          pointListEquals(other.points, points) &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.arrowType == arrowType &&
          other.startArrowhead == startArrowhead &&
          other.endArrowhead == endArrowhead &&
          other.startBinding == startBinding &&
          other.endBinding == endBinding &&
          fixedSegmentListEquals(other.fixedSegments, fixedSegments) &&
          other.startIsSpecial == startIsSpecial &&
          other.endIsSpecial == endIsSpecial;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    color,
    strokeWidth,
    strokeStyle,
    arrowType,
    startArrowhead,
    endArrowhead,
    startBinding,
    endBinding,
    fixedSegments == null ? null : Object.hashAll(fixedSegments!),
    startIsSpecial,
    endIsSpecial,
  );

  static ArrowBinding? _decodeBinding(Object? raw) {
    final map = _asJsonMap(raw);
    if (map == null) {
      return null;
    }
    return ArrowBinding.fromJson(map);
  }

  static List<ElbowFixedSegment>? _decodeFixedSegments(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final segments = <ElbowFixedSegment>[];
    for (final entry in raw) {
      final map = _asJsonMap(entry);
      if (map == null) {
        continue;
      }
      try {
        segments.add(ElbowFixedSegment.fromJson(map));
      } on FormatException {
        // Skip invalid segment entries.
      }
    }
    return _normalizeFixedSegments(segments);
  }

  static List<ElbowFixedSegment>? _normalizeFixedSegments(
    List<ElbowFixedSegment>? segments,
  ) {
    if (segments == null || segments.isEmpty) {
      return null;
    }
    return List<ElbowFixedSegment>.unmodifiable(segments);
  }

  static Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }

    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      map[key] = entry.value;
    }
    return map;
  }

  static DrawColor _resolveColor(DrawColor? next, DrawColor fallback) =>
      next ?? fallback;
}
