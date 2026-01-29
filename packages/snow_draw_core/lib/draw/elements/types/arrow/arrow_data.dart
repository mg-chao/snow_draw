import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';
import 'arrow_binding.dart';
import 'elbow/elbow_fixed_segment.dart';

@immutable
final class ArrowData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  static const _startBindingUnset = Object();
  static const _endBindingUnset = Object();
  static const _fixedSegmentsUnset = Object();
  static const _startIsSpecialUnset = Object();
  static const _endIsSpecialUnset = Object();

  const ArrowData({
    this.points = const [DrawPoint.zero, DrawPoint(x: 1, y: 1)],
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
    color: Color(
      (json['color'] as int?) ?? ConfigDefaults.defaultColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultStrokeWidth,
    strokeStyle: StrokeStyle.values.firstWhere(
      (style) => style.name == json['strokeStyle'],
      orElse: () => ConfigDefaults.defaultStrokeStyle,
    ),
    arrowType: _decodeArrowType(json['arrowType']),
    startArrowhead: ArrowheadStyle.values.firstWhere(
      (style) => style.name == json['startArrowhead'],
      orElse: () => ConfigDefaults.defaultStartArrowhead,
    ),
    endArrowhead: ArrowheadStyle.values.firstWhere(
      (style) => style.name == json['endArrowhead'],
      orElse: () => ConfigDefaults.defaultEndArrowhead,
    ),
    startBinding: _decodeBinding(json['startBinding']),
    endBinding: _decodeBinding(json['endBinding']),
    fixedSegments: _decodeFixedSegments(json['fixedSegments']),
    startIsSpecial: json['startIsSpecial'] as bool?,
    endIsSpecial: json['endIsSpecial'] as bool?,
  );

  static const typeIdToken = ElementTypeId<ArrowData>('arrow');

  /// Normalized control points in element-local space (0..1).
  final List<DrawPoint> points;
  final Color color;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final ArrowType arrowType;
  final ArrowheadStyle startArrowhead;
  final ArrowheadStyle endArrowhead;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;

  @override
  ElementTypeId<ArrowData> get typeId => ArrowData.typeIdToken;

  ArrowData copyWith({
    List<DrawPoint>? points,
    Color? color,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    Object? startBinding = _startBindingUnset,
    Object? endBinding = _endBindingUnset,
    Object? fixedSegments = _fixedSegmentsUnset,
    Object? startIsSpecial = _startIsSpecialUnset,
    Object? endIsSpecial = _endIsSpecialUnset,
  }) => ArrowData(
    points: points == null ? this.points : List<DrawPoint>.unmodifiable(points),
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    arrowType: arrowType ?? this.arrowType,
    startArrowhead: startArrowhead ?? this.startArrowhead,
    endArrowhead: endArrowhead ?? this.endArrowhead,
    startBinding: startBinding == _startBindingUnset
        ? this.startBinding
        : startBinding as ArrowBinding?,
    endBinding: endBinding == _endBindingUnset
        ? this.endBinding
        : endBinding as ArrowBinding?,
    fixedSegments: fixedSegments == _fixedSegmentsUnset
        ? this.fixedSegments
        : _coerceFixedSegments(fixedSegments as List<ElbowFixedSegment>?),
    startIsSpecial: startIsSpecial == _startIsSpecialUnset
        ? this.startIsSpecial
        : startIsSpecial as bool?,
    endIsSpecial: endIsSpecial == _endIsSpecialUnset
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
    color: update.color ?? color,
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
      return const [DrawPoint.zero, DrawPoint(x: 1, y: 1)];
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static ArrowType _decodeArrowType(Object? raw) {
    if (raw is String) {
      return ArrowType.values.firstWhere(
        (style) => style.name == raw,
        orElse: () => ConfigDefaults.defaultArrowType,
      );
    }
    return ConfigDefaults.defaultArrowType;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowData &&
          _pointsEqual(other.points, points) &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.arrowType == arrowType &&
          other.startArrowhead == startArrowhead &&
          other.endArrowhead == endArrowhead &&
          other.startBinding == startBinding &&
          other.endBinding == endBinding &&
          _fixedSegmentsEqual(other.fixedSegments, fixedSegments) &&
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

  static bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _fixedSegmentsEqual(
    List<ElbowFixedSegment>? a,
    List<ElbowFixedSegment>? b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return a == null && b == null;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static ArrowBinding? _decodeBinding(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return ArrowBinding.fromJson(raw);
    }
    if (raw is Map) {
      return ArrowBinding.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  static List<ElbowFixedSegment>? _decodeFixedSegments(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final segments = <ElbowFixedSegment>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        try {
          segments.add(ElbowFixedSegment.fromJson(entry));
        } on FormatException {
          // Skip invalid segment entries.
        }
      } else if (entry is Map) {
        try {
          segments.add(ElbowFixedSegment.fromJson(entry.cast<String, dynamic>()));
        } on FormatException {
          // Skip invalid segment entries.
        }
      }
    }
    if (segments.isEmpty) {
      return null;
    }
    return List<ElbowFixedSegment>.unmodifiable(segments);
  }

  static List<ElbowFixedSegment>? _coerceFixedSegments(
    List<ElbowFixedSegment>? segments,
  ) {
    if (segments == null || segments.isEmpty) {
      return null;
    }
    return List<ElbowFixedSegment>.unmodifiable(segments);
  }
}
