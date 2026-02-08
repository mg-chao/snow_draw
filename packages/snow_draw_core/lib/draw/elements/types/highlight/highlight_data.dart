import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class HighlightData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  const HighlightData({
    this.shape = ConfigDefaults.defaultHighlightShape,
    this.color = ConfigDefaults.defaultHighlightColor,
    this.strokeColor = ConfigDefaults.defaultHighlightColor,
    this.strokeWidth = 0,
  });

  factory HighlightData.fromJson(Map<String, dynamic> json) => HighlightData(
    shape: HighlightShape.values.firstWhere(
      (shape) => shape.name == json['shape'],
      orElse: () => ConfigDefaults.defaultHighlightShape,
    ),
    color: Color(
      (json['color'] as int?) ??
          ConfigDefaults.defaultHighlightColor.toARGB32(),
    ),
    strokeColor: Color(
      (json['strokeColor'] as int?) ??
          ConfigDefaults.defaultHighlightColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultTextStrokeWidth,
  );

  static const typeIdToken = ElementTypeId<HighlightData>('highlight');

  final HighlightShape shape;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;

  @override
  ElementTypeId<HighlightData> get typeId => HighlightData.typeIdToken;

  HighlightData copyWith({
    HighlightShape? shape,
    Color? color,
    Color? strokeColor,
    double? strokeWidth,
  }) => HighlightData(
    shape: shape ?? this.shape,
    color: color ?? this.color,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    strokeColor: style.textStrokeColor,
    strokeWidth: style.textStrokeWidth,
    shape: style.highlightShape,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: update.color ?? color,
    strokeColor: update.textStrokeColor ?? strokeColor,
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
      identical(this, other) ||
      other is HighlightData &&
          other.shape == shape &&
          other.color == color &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(shape, color, strokeColor, strokeWidth);
}
