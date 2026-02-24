import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_color.dart';
import '../../../types/element_style.dart';
import '../../../utils/string_normalization.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';
import '../shared/element_data_codec.dart';

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
    text: json['text'] as String,
    color: DrawColor(json['color'] as int),
    fontSize: (json['fontSize'] as num).toDouble(),
    fontFamily: normalizeOptionalTrimmedString(
      _decodeNullableString(json['fontFamily'], fieldName: 'fontFamily'),
    ),
    horizontalAlign: ElementDataCodec.decodeEnumByName(
      values: TextHorizontalAlign.values,
      raw: json['horizontalAlign'],
      fieldName: 'horizontalAlign',
    ),
    verticalAlign: ElementDataCodec.decodeEnumByName(
      values: TextVerticalAlign.values,
      raw: json['verticalAlign'],
      fieldName: 'verticalAlign',
    ),
    fillColor: DrawColor(json['fillColor'] as int),
    fillStyle: ElementDataCodec.decodeEnumByName(
      values: FillStyle.values,
      raw: json['fillStyle'],
      fieldName: 'fillStyle',
    ),
    strokeColor: DrawColor(json['strokeColor'] as int),
    strokeWidth: (json['strokeWidth'] as num).toDouble(),
    cornerRadius: (json['cornerRadius'] as num).toDouble(),
    autoResize: _decodeBool(json['autoResize'], fieldName: 'autoResize'),
  );

  static const typeIdToken = ElementTypeId<TextData>('text');

  final String text;
  final DrawColor color;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final TextVerticalAlign verticalAlign;
  final DrawColor fillColor;
  final FillStyle fillStyle;
  final DrawColor strokeColor;
  final double strokeWidth;
  final double cornerRadius;
  final bool autoResize;

  @override
  ElementTypeId<TextData> get typeId => TextData.typeIdToken;

  TextData copyWith({
    String? text,
    DrawColor? color,
    double? fontSize,
    Object? fontFamily = _fontFamilyUnset,
    TextHorizontalAlign? horizontalAlign,
    TextVerticalAlign? verticalAlign,
    DrawColor? fillColor,
    FillStyle? fillStyle,
    DrawColor? strokeColor,
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
    return normalizeOptionalTrimmedString(fontFamily as String?);
  }
}

String? _decodeNullableString(Object? raw, {required String fieldName}) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return raw;
  }
  throw FormatException('Expected string for $fieldName');
}

bool _decodeBool(Object? raw, {required String fieldName}) {
  if (raw is bool) {
    return raw;
  }
  throw FormatException('Expected bool for $fieldName');
}
