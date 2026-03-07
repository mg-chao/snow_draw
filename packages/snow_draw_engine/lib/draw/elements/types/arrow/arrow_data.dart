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
import '../connector/connector_data.dart';
import '../connector/connector_data_codec.dart';
import '../shared/element_data_codec.dart';
import 'arrow_binding.dart';
import 'elbow/elbow_fixed_segment.dart';
import 'elbow/elbow_routing_data.dart';

@immutable
final class ArrowData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData
    implements ConnectorData {
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
    this.elbowRoutingData,
  });

  factory ArrowData.fromJson(Map<String, dynamic> json) {
    final arrowType = ElementDataCodec.decodeEnumByName(
      values: ArrowType.values,
      raw: json['arrowType'],
      fieldName: 'arrowType',
    );
    return ArrowData(
      points: ConnectorDataCodec.decodePoints(json['points']),
      color: DrawColor(json['color'] as int),
      strokeWidth: ElementDataCodec.decodeDouble(
        json['strokeWidth'],
        fieldName: 'strokeWidth',
      ),
      strokeStyle: ElementDataCodec.decodeEnumByName(
        values: StrokeStyle.values,
        raw: json['strokeStyle'],
        fieldName: 'strokeStyle',
      ),
      arrowType: arrowType,
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
      startBinding: ConnectorDataCodec.decodeBinding(json['startBinding']),
      endBinding: ConnectorDataCodec.decodeBinding(json['endBinding']),
      elbowRoutingData: arrowType == ArrowType.elbow
          ? ConnectorDataCodec.decodeElbowRoutingData(
              rawFixedSegments: json['fixedSegments'],
              rawStartIsSpecial: json['startIsSpecial'],
              rawEndIsSpecial: json['endIsSpecial'],
            )
          : null,
    );
  }

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
  final ElbowRoutingData? elbowRoutingData;
  @override
  List<ElbowFixedSegment>? get fixedSegments => elbowRoutingData?.fixedSegments;
  @override
  bool? get startIsSpecial => elbowRoutingData?.startIsSpecial;
  @override
  bool? get endIsSpecial => elbowRoutingData?.endIsSpecial;

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
    Object? startBinding = ConnectorData.unset,
    Object? endBinding = ConnectorData.unset,
    Object? fixedSegments = ConnectorData.unset,
    Object? startIsSpecial = ConnectorData.unset,
    Object? endIsSpecial = ConnectorData.unset,
  }) {
    final nextArrowType = arrowType ?? this.arrowType;
    return ArrowData(
      points: points == null
          ? this.points
          : List<DrawPoint>.unmodifiable(points),
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      arrowType: nextArrowType,
      startArrowhead: startArrowhead ?? this.startArrowhead,
      endArrowhead: endArrowhead ?? this.endArrowhead,
      startBinding: ConnectorDataCodec.resolveBindingUpdate(
        rawBinding: startBinding,
        currentBinding: this.startBinding,
      ),
      endBinding: ConnectorDataCodec.resolveBindingUpdate(
        rawBinding: endBinding,
        currentBinding: this.endBinding,
      ),
      elbowRoutingData: nextArrowType == ArrowType.elbow
          ? ConnectorDataCodec.resolveElbowRoutingUpdate(
              rawFixedSegments: fixedSegments,
              rawStartIsSpecial: startIsSpecial,
              rawEndIsSpecial: endIsSpecial,
              currentRoutingData: elbowRoutingData,
            )
          : null,
    );
  }

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
    'points': ConnectorDataCodec.encodePoints(points),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'arrowType': arrowType.name,
    'startArrowhead': startArrowhead.name,
    'endArrowhead': endArrowhead.name,
    'startBinding': startBinding?.toJson(),
    'endBinding': endBinding?.toJson(),
    'fixedSegments': ConnectorDataCodec.encodeFixedSegments(
      elbowRoutingData?.fixedSegments,
    ),
    'startIsSpecial': elbowRoutingData?.startIsSpecial,
    'endIsSpecial': elbowRoutingData?.endIsSpecial,
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
          other.elbowRoutingData == elbowRoutingData;

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
    elbowRoutingData,
  );
}
