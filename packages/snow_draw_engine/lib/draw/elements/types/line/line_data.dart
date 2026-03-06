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
import '../arrow/arrow_binding.dart';
import '../connector/connector_data.dart';
import '../connector/connector_data_codec.dart';
import '../arrow/elbow/elbow_fixed_segment.dart';
import '../shared/element_data_codec.dart';

@immutable
final class LineData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData
    implements ConnectorData {
  static const List<DrawPoint> _defaultPoints = [
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  const LineData({
    this.points = _defaultPoints,
    this.color = ConfigDefaults.defaultColor,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
    this.startBinding,
    this.endBinding,
  }) : arrowType = ArrowType.curved,
       startArrowhead = ArrowheadStyle.none,
       endArrowhead = ArrowheadStyle.none;

  factory LineData.fromJson(Map<String, dynamic> json) => LineData(
    points: ConnectorDataCodec.decodePoints(json['points']),
    color: DrawColor(json['color'] as int),
    fillColor: DrawColor(json['fillColor'] as int),
    strokeWidth: ElementDataCodec.decodeDouble(
      json['strokeWidth'],
      fieldName: 'strokeWidth',
    ),
    strokeStyle: ElementDataCodec.decodeEnumByName(
      values: StrokeStyle.values,
      raw: json['strokeStyle'],
      fieldName: 'strokeStyle',
    ),
    fillStyle: ElementDataCodec.decodeEnumByName(
      values: FillStyle.values,
      raw: json['fillStyle'],
      fieldName: 'fillStyle',
    ),
    startBinding: ConnectorDataCodec.decodeBinding(json['startBinding']),
    endBinding: ConnectorDataCodec.decodeBinding(json['endBinding']),
  );

  static const typeIdToken = ElementTypeId<LineData>('line');

  /// Normalized control points in element-local space (0..1).
  @override
  final List<DrawPoint> points;
  final DrawColor color;
  final DrawColor fillColor;
  final FillStyle fillStyle;
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
  List<ElbowFixedSegment>? get fixedSegments => null;
  @override
  bool? get startIsSpecial => null;
  @override
  bool? get endIsSpecial => null;

  @override
  ElementTypeId<LineData> get typeId => LineData.typeIdToken;

  @override
  LineData copyWith({
    List<DrawPoint>? points,
    DrawColor? color,
    DrawColor? fillColor,
    FillStyle? fillStyle,
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
    assert(
      arrowType == null || arrowType == ArrowType.curved,
      'LineData only supports curved arrow type',
    );
    assert(
      startArrowhead == null || startArrowhead == ArrowheadStyle.none,
      'LineData does not support start arrowheads',
    );
    assert(
      endArrowhead == null || endArrowhead == ArrowheadStyle.none,
      'LineData does not support end arrowheads',
    );
    return LineData(
      points: points == null
          ? this.points
          : List<DrawPoint>.unmodifiable(points),
      color: color ?? this.color,
      fillColor: fillColor ?? this.fillColor,
      fillStyle: fillStyle ?? this.fillStyle,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      startBinding: ConnectorDataCodec.resolveBindingUpdate(
        rawBinding: startBinding,
        currentBinding: this.startBinding,
      ),
      endBinding: ConnectorDataCodec.resolveBindingUpdate(
        rawBinding: endBinding,
        currentBinding: this.endBinding,
      ),
    );
  }

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    fillColor: style.fillColor,
    fillStyle: style.fillStyle,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: update.color,
    fillColor: update.fillColor,
    fillStyle: update.fillStyle ?? fillStyle,
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'points': ConnectorDataCodec.encodePoints(points),
    'color': color.toARGB32(),
    'fillColor': fillColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'fillStyle': fillStyle.name,
    'arrowType': arrowType.name,
    'startArrowhead': startArrowhead.name,
    'endArrowhead': endArrowhead.name,
    'startBinding': startBinding?.toJson(),
    'endBinding': endBinding?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineData &&
          pointListEquals(other.points, points) &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.startBinding == startBinding &&
          other.endBinding == endBinding;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    color,
    fillColor,
    fillStyle,
    strokeWidth,
    strokeStyle,
    startBinding,
    endBinding,
  );
}
