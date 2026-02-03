import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class TextData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  static const _fontFamilyUnset = Object();

  const TextData({
    this.text = '',
    this.color = ConfigDefaults.defaultColor,
    this.fontSize = ConfigDefaults.defaultTextFontSize,
    this.fontFamily = ConfigDefaults.defaultTextFontFamily,
    this.horizontalAlign = ConfigDefaults.defaultTextHorizontalAlign,
    this.verticalAlign = ConfigDefaults.defaultTextVerticalAlign,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
    this.strokeColor = ConfigDefaults.defaultTextStrokeColor,
    this.strokeWidth = ConfigDefaults.defaultTextStrokeWidth,
    this.cornerRadius = ConfigDefaults.defaultTextCornerRadius,
    bool? autoResize,
  }) : autoResize = autoResize ?? ConfigDefaults.defaultTextAutoResize;

  factory TextData.fromJson(Map<String, dynamic> json) => TextData(
    text: json['text'] as String? ?? '',
    color: Color(
      (json['color'] as int?) ?? ConfigDefaults.defaultColor.toARGB32(),
    ),
    fontSize:
        (json['fontSize'] as num?)?.toDouble() ??
        ConfigDefaults.defaultTextFontSize,
    fontFamily: (json['fontFamily'] as String?)?.trim().isEmpty ?? true
        ? null
        : json['fontFamily'] as String?,
    horizontalAlign: TextHorizontalAlign.values.firstWhere(
      (value) => value.name == json['horizontalAlign'],
      orElse: () => ConfigDefaults.defaultTextHorizontalAlign,
    ),
    verticalAlign: TextVerticalAlign.values.firstWhere(
      (value) => value.name == json['verticalAlign'],
      orElse: () => ConfigDefaults.defaultTextVerticalAlign,
    ),
    fillColor: Color(
      (json['fillColor'] as int?) ?? ConfigDefaults.defaultFillColor.toARGB32(),
    ),
    fillStyle: FillStyle.values.firstWhere(
      (style) => style.name == json['fillStyle'],
      orElse: () => ConfigDefaults.defaultFillStyle,
    ),
    strokeColor: Color(
      (json['strokeColor'] as int?) ??
          ConfigDefaults.defaultTextStrokeColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultTextStrokeWidth,
    cornerRadius:
        (json['cornerRadius'] as num?)?.toDouble() ??
        ConfigDefaults.defaultTextCornerRadius,
    autoResize:
        json['autoResize'] as bool? ?? ConfigDefaults.defaultTextAutoResize,
  );

  static const typeIdToken = ElementTypeId<TextData>('text');

  final String text;
  final Color color;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final TextVerticalAlign verticalAlign;
  final Color fillColor;
  final FillStyle fillStyle;
  final Color strokeColor;
  final double strokeWidth;
  final double cornerRadius;
  final bool autoResize;

  @override
  ElementTypeId<TextData> get typeId => TextData.typeIdToken;

  TextData copyWith({
    String? text,
    Color? color,
    double? fontSize,
    Object? fontFamily = _fontFamilyUnset,
    TextHorizontalAlign? horizontalAlign,
    TextVerticalAlign? verticalAlign,
    Color? fillColor,
    FillStyle? fillStyle,
    Color? strokeColor,
    double? strokeWidth,
    double? cornerRadius,
    bool? autoResize,
  }) => TextData(
    text: text ?? this.text,
    color: color ?? this.color,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily == _fontFamilyUnset
        ? this.fontFamily
        : fontFamily as String?,
    horizontalAlign: horizontalAlign ?? this.horizontalAlign,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    fillColor: fillColor ?? this.fillColor,
    fillStyle: fillStyle ?? this.fillStyle,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    autoResize: autoResize ?? this.autoResize,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    fontSize: style.fontSize,
    fontFamily: style.fontFamily?.trim().isEmpty ?? true
        ? null
        : style.fontFamily,
    horizontalAlign: style.textAlign,
    verticalAlign: style.verticalAlign,
    fillColor: style.fillColor,
    fillStyle: style.fillStyle,
    strokeColor: style.textStrokeColor,
    strokeWidth: style.textStrokeWidth,
    cornerRadius: style.cornerRadius,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: update.color ?? color,
    fontSize: update.fontSize ?? fontSize,
    fontFamily: update.fontFamily == null
        ? fontFamily
        : (update.fontFamily!.trim().isEmpty ? null : update.fontFamily),
    horizontalAlign: update.textAlign ?? horizontalAlign,
    verticalAlign: update.verticalAlign ?? verticalAlign,
    fillColor: update.fillColor ?? fillColor,
    fillStyle: update.fillStyle ?? fillStyle,
    strokeColor: update.textStrokeColor ?? strokeColor,
    strokeWidth: update.textStrokeWidth ?? strokeWidth,
    cornerRadius: update.cornerRadius ?? cornerRadius,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
    'fontFamily': fontFamily ?? '',
    'horizontalAlign': horizontalAlign.name,
    'verticalAlign': verticalAlign.name,
    'fillColor': fillColor.toARGB32(),
    'fillStyle': fillStyle.name,
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'cornerRadius': cornerRadius,
    'autoResize': autoResize,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextData &&
          other.text == text &&
          other.color == color &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.verticalAlign == verticalAlign &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth &&
          other.cornerRadius == cornerRadius &&
          other.autoResize == autoResize;

  @override
  int get hashCode => Object.hash(
    text,
    color,
    fontSize,
    fontFamily,
    horizontalAlign,
    verticalAlign,
    fillColor,
    fillStyle,
    strokeColor,
    strokeWidth,
    cornerRadius,
    autoResize,
  );
}
