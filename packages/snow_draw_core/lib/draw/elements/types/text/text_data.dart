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
    fontFamily: _normalizeOptionalString(json['fontFamily'] as String?),
    horizontalAlign: _decodeEnum(
      values: TextHorizontalAlign.values,
      raw: json['horizontalAlign'],
      fallback: ConfigDefaults.defaultTextHorizontalAlign,
    ),
    verticalAlign: _decodeEnum(
      values: TextVerticalAlign.values,
      raw: json['verticalAlign'],
      fallback: ConfigDefaults.defaultTextVerticalAlign,
    ),
    fillColor: Color(
      (json['fillColor'] as int?) ?? ConfigDefaults.defaultFillColor.toARGB32(),
    ),
    fillStyle: _decodeEnum(
      values: FillStyle.values,
      raw: json['fillStyle'],
      fallback: ConfigDefaults.defaultFillStyle,
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
    fontFamily: _resolveCopyWithFontFamily(fontFamily, this.fontFamily),
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
    fontFamily: style.fontFamily,
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
    color: update.color,
    fontSize: update.fontSize,
    fontFamily: update.fontFamily ?? _fontFamilyUnset,
    horizontalAlign: update.textAlign,
    verticalAlign: update.verticalAlign,
    fillColor: update.fillColor,
    fillStyle: update.fillStyle,
    strokeColor: update.textStrokeColor,
    strokeWidth: update.textStrokeWidth,
    cornerRadius: update.cornerRadius,
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

  static String? _resolveCopyWithFontFamily(
    Object? fontFamily,
    String? currentFontFamily,
  ) {
    if (identical(fontFamily, _fontFamilyUnset)) {
      return currentFontFamily;
    }
    return _normalizeOptionalString(fontFamily as String?);
  }

  static String? _normalizeOptionalString(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
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
}
