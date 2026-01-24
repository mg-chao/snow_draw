import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class RectangleData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  const RectangleData({
    this.cornerRadius = ConfigDefaults.defaultCornerRadius,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.color = ConfigDefaults.defaultColor,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
  });

  factory RectangleData.fromJson(Map<String, dynamic> json) => RectangleData(
    cornerRadius:
        (json['cornerRadius'] as num?)?.toDouble() ??
        ConfigDefaults.defaultCornerRadius,
    fillColor: Color(
      (json['fillColor'] as int?) ??
          ConfigDefaults.defaultFillColor.toARGB32(),
    ),
    color: Color(
      (json['color'] as int?) ??
          (json['strokeColor'] as int?) ??
          ConfigDefaults.defaultColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultStrokeWidth,
    strokeStyle: StrokeStyle.values.firstWhere(
      (style) => style.name == json['strokeStyle'],
      orElse: () => ConfigDefaults.defaultStrokeStyle,
    ),
    fillStyle: FillStyle.values.firstWhere(
      (style) => style.name == json['fillStyle'],
      orElse: () => ConfigDefaults.defaultFillStyle,
    ),
  );
  static const typeIdToken = ElementTypeId<RectangleData>('rectangle');

  final double cornerRadius;
  final Color fillColor;
  final Color color;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final FillStyle fillStyle;

  @override
  ElementTypeId<RectangleData> get typeId => RectangleData.typeIdToken;

  RectangleData copyWith({
    double? cornerRadius,
    Color? fillColor,
    Color? color,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
  }) => RectangleData(
    cornerRadius: cornerRadius ?? this.cornerRadius,
    fillColor: fillColor ?? this.fillColor,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    fillStyle: fillStyle ?? this.fillStyle,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    fillColor: style.fillColor,
    color: style.color,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
    fillStyle: style.fillStyle,
    cornerRadius: style.cornerRadius,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    cornerRadius: update.cornerRadius ?? cornerRadius,
    fillColor: update.fillColor ?? fillColor,
    color: update.color ?? color,
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
    fillStyle: update.fillStyle ?? fillStyle,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'cornerRadius': cornerRadius,
    'fillColor': fillColor.toARGB32(),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'fillStyle': fillStyle.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RectangleData &&
          other.cornerRadius == cornerRadius &&
          other.fillColor == fillColor &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.fillStyle == fillStyle;

  @override
  int get hashCode =>
      Object.hash(
        cornerRadius,
        fillColor,
        color,
        strokeWidth,
        strokeStyle,
        fillStyle,
      );
}
