import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class SerialNumberData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  static const _fontFamilyUnset = Object();
  static const _textElementIdUnset = Object();

  const SerialNumberData({
    this.number = ConfigDefaults.defaultSerialNumber,
    this.color = ConfigDefaults.defaultColor,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
    this.fontSize = ConfigDefaults.defaultSerialNumberFontSize,
    this.fontFamily = ConfigDefaults.defaultTextFontFamily,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
    this.textElementId,
  });

  factory SerialNumberData.fromJson(
    Map<String, dynamic> json,
  ) => SerialNumberData(
    number: _coerceNumber(
      (json['number'] as num?)?.toInt(),
      ConfigDefaults.defaultSerialNumber,
    ),
    color: Color(
      (json['color'] as int?) ?? ConfigDefaults.defaultColor.toARGB32(),
    ),
    fillColor: Color(
      (json['fillColor'] as int?) ?? ConfigDefaults.defaultFillColor.toARGB32(),
    ),
    fillStyle: FillStyle.values.firstWhere(
      (style) => style.name == json['fillStyle'],
      orElse: () => ConfigDefaults.defaultFillStyle,
    ),
    fontSize:
        (json['fontSize'] as num?)?.toDouble() ??
        ConfigDefaults.defaultSerialNumberFontSize,
    fontFamily: (json['fontFamily'] as String?)?.trim().isEmpty ?? true
        ? null
        : json['fontFamily'] as String?,
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultStrokeWidth,
    strokeStyle: StrokeStyle.values.firstWhere(
      (style) => style.name == json['strokeStyle'],
      orElse: () => ConfigDefaults.defaultStrokeStyle,
    ),
    textElementId: (json['textElementId'] as String?)?.trim().isEmpty ?? true
        ? null
        : json['textElementId'] as String?,
  );

  static const typeIdToken = ElementTypeId<SerialNumberData>('serial_number');

  final int number;
  final Color color;
  final Color fillColor;
  final FillStyle fillStyle;
  final double fontSize;
  final String? fontFamily;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final String? textElementId;

  @override
  ElementTypeId<SerialNumberData> get typeId => SerialNumberData.typeIdToken;

  SerialNumberData copyWith({
    int? number,
    Color? color,
    Color? fillColor,
    FillStyle? fillStyle,
    double? fontSize,
    Object? fontFamily = _fontFamilyUnset,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    Object? textElementId = _textElementIdUnset,
  }) => SerialNumberData(
    number: _coerceNumber(number, this.number),
    color: color ?? this.color,
    fillColor: fillColor ?? this.fillColor,
    fillStyle: fillStyle ?? this.fillStyle,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: _resolveFontFamily(fontFamily, this.fontFamily),
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    textElementId: textElementId == _textElementIdUnset
        ? this.textElementId
        : textElementId as String?,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    number: style.serialNumber,
    color: style.color,
    fillColor: style.fillColor,
    fillStyle: style.fillStyle,
    fontSize: style.fontSize,
    fontFamily: style.fontFamily?.trim().isEmpty ?? true
        ? null
        : style.fontFamily,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    number: update.serialNumber ?? number,
    color: update.color ?? color,
    fillColor: update.fillColor ?? fillColor,
    fillStyle: update.fillStyle ?? fillStyle,
    fontSize: update.fontSize ?? fontSize,
    fontFamily: update.fontFamily == null
        ? fontFamily
        : (update.fontFamily!.trim().isEmpty ? null : update.fontFamily),
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'number': number,
    'color': color.toARGB32(),
    'fillColor': fillColor.toARGB32(),
    'fillStyle': fillStyle.name,
    'fontSize': fontSize,
    'fontFamily': fontFamily ?? '',
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'textElementId': textElementId ?? '',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialNumberData &&
          other.number == number &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.textElementId == textElementId;

  @override
  int get hashCode => Object.hash(
    number,
    color,
    fillColor,
    fillStyle,
    fontSize,
    fontFamily,
    strokeWidth,
    strokeStyle,
    textElementId,
  );
}

int _coerceNumber(int? value, int fallback) {
  final resolved = value ?? fallback;
  return resolved < 0 ? 0 : resolved;
}

String? _resolveFontFamily(Object? value, String? fallback) {
  if (value == SerialNumberData._fontFamilyUnset) {
    return fallback;
  }
  final raw = value as String?;
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
