import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_color.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';
import '../shared/element_data_codec.dart';

@immutable
final class HighlightData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  const HighlightData({
    this.shape = ConfigDefaults.defaultHighlightShape,
    this.color = ConfigDefaults.defaultHighlightColor,
    this.strokeColor = ConfigDefaults.defaultHighlightStrokeColor,
    this.strokeWidth = 0,
  });

  factory HighlightData.fromJson(Map<String, dynamic> json) => HighlightData(
    shape: ElementDataCodec.decodeEnumByName(
      values: HighlightShape.values,
      raw: json['shape'],
      fieldName: 'shape',
    ),
    color: DrawColor(json['color'] as int),
    strokeColor: DrawColor(json['strokeColor'] as int),
    strokeWidth: ElementDataCodec.decodeDouble(
      json['strokeWidth'],
      fieldName: 'strokeWidth',
    ),
  );

  static const typeIdToken = ElementTypeId<HighlightData>('highlight');

  final HighlightShape shape;
  final DrawColor color;
  final DrawColor strokeColor;
  final double strokeWidth;

  @override
  ElementTypeId<HighlightData> get typeId => HighlightData.typeIdToken;

  HighlightData copyWith({
    HighlightShape? shape,
    DrawColor? color,
    DrawColor? strokeColor,
    double? strokeWidth,
  }) => HighlightData(
    shape: shape ?? this.shape,
    color: color ?? this.color,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );

  @override
  HighlightData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    strokeColor: style.textStrokeColor,
    strokeWidth: style.textStrokeWidth,
    shape: style.highlightShape,
  );

  @override
  HighlightData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: update.color,
    strokeColor: update.textStrokeColor,
    strokeWidth: update.textStrokeWidth ?? strokeWidth,
    shape: update.highlightShape ?? shape,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'shape': shape.name,
    'color': color.toARGB32(),
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
  };

  @override
  bool operator ==(Object other) =>
      other is HighlightData &&
      other.shape == shape &&
      other.color == color &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(shape, color, strokeColor, strokeWidth);
}
