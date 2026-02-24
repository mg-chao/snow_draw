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
import '../shared/element_data_codec.dart';
import 'arrow_binding.dart';
import 'arrow_like_data.dart';
import 'arrow_like_data_codec.dart';
import 'elbow/elbow_fixed_segment.dart';

@immutable
final class ArrowData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData
    implements ArrowLikeData {
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
    points: ArrowLikeDataCodec.decodePoints(json['points']),
    color: DrawColor(json['color'] as int),
    strokeWidth: (json['strokeWidth'] as num).toDouble(),
    strokeStyle: ElementDataCodec.decodeEnumByName(
      values: StrokeStyle.values,
      raw: json['strokeStyle'],
      fieldName: 'strokeStyle',
    ),
    arrowType: ElementDataCodec.decodeEnumByName(
      values: ArrowType.values,
      raw: json['arrowType'],
      fieldName: 'arrowType',
    ),
    startArrowhead: ElementDataCodec.decodeEnumByName(
      values: ArrowheadStyle.values,
      raw: json['startArrowhead'],
      fieldName: 'startArrowhead',
    ),
    endArrowhead: ElementDataCodec.decodeEnumByName(
      values: ArrowheadStyle.values,
      raw: json['endArrowhead'],
      fieldName: 'endArrowhead',
    ),
    startBinding: ArrowLikeDataCodec.decodeBinding(json['startBinding']),
    endBinding: ArrowLikeDataCodec.decodeBinding(json['endBinding']),
    fixedSegments: ArrowLikeDataCodec.decodeFixedSegments(
      json['fixedSegments'],
    ),
    startIsSpecial: ElementDataCodec.decodeNullableBool(
      json['startIsSpecial'],
      fieldName: 'startIsSpecial',
    ),
    endIsSpecial: ElementDataCodec.decodeNullableBool(
      json['endIsSpecial'],
      fieldName: 'endIsSpecial',
    ),
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
    Object? startBinding = ArrowLikeData.unset,
    Object? endBinding = ArrowLikeData.unset,
    Object? fixedSegments = ArrowLikeData.unset,
    Object? startIsSpecial = ArrowLikeData.unset,
    Object? endIsSpecial = ArrowLikeData.unset,
  }) => ArrowData(
    points: points == null ? this.points : List<DrawPoint>.unmodifiable(points),
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    arrowType: arrowType ?? this.arrowType,
    startArrowhead: startArrowhead ?? this.startArrowhead,
    endArrowhead: endArrowhead ?? this.endArrowhead,
    startBinding: ArrowLikeDataCodec.resolveBindingUpdate(
      rawBinding: startBinding,
      currentBinding: this.startBinding,
    ),
    endBinding: ArrowLikeDataCodec.resolveBindingUpdate(
      rawBinding: endBinding,
      currentBinding: this.endBinding,
    ),
    fixedSegments: ArrowLikeDataCodec.resolveFixedSegmentsUpdate(
      rawFixedSegments: fixedSegments,
      currentFixedSegments: this.fixedSegments,
    ),
    startIsSpecial: ArrowLikeDataCodec.resolveNullableBoolUpdate(
      rawValue: startIsSpecial,
      currentValue: this.startIsSpecial,
    ),
    endIsSpecial: ArrowLikeDataCodec.resolveNullableBoolUpdate(
      rawValue: endIsSpecial,
      currentValue: this.endIsSpecial,
    ),
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
    color: update.color,
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
    arrowType: update.arrowType ?? arrowType,
    startArrowhead: update.startArrowhead ?? startArrowhead,
    endArrowhead: update.endArrowhead ?? endArrowhead,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'points': ArrowLikeDataCodec.encodePoints(points),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'arrowType': arrowType.name,
    'startArrowhead': startArrowhead.name,
    'endArrowhead': endArrowhead.name,
    'startBinding': startBinding?.toJson(),
    'endBinding': endBinding?.toJson(),
    'fixedSegments': ArrowLikeDataCodec.encodeFixedSegments(fixedSegments),
    'startIsSpecial': startIsSpecial,
    'endIsSpecial': endIsSpecial,
  };

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
}
