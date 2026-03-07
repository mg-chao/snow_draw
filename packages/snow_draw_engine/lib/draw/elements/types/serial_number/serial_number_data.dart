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

  factory SerialNumberData.fromJson(Map<String, dynamic> json) =>
      SerialNumberData(
        number: _clampNonNegative(
          ElementDataCodec.decodeInt(json['number'], fieldName: 'number'),
        ),
        color: DrawColor(json['color'] as int),
        fillColor: DrawColor(json['fillColor'] as int),
        fillStyle: ElementDataCodec.decodeEnumByName(
          values: FillStyle.values,
          raw: json['fillStyle'],
          fieldName: 'fillStyle',
        ),
        fontSize: ElementDataCodec.decodeDouble(
          json['fontSize'],
          fieldName: 'fontSize',
        ),
        fontFamily: normalizeOptionalTrimmedString(
          ElementDataCodec.decodeNullableString(
            json['fontFamily'],
            fieldName: 'fontFamily',
          ),
        ),
        strokeWidth: ElementDataCodec.decodeDouble(
          json['strokeWidth'],
          fieldName: 'strokeWidth',
        ),
        strokeStyle: ElementDataCodec.decodeEnumByName(
          values: StrokeStyle.values,
          raw: json['strokeStyle'],
          fieldName: 'strokeStyle',
        ),
        textElementId: normalizeOptionalTrimmedString(
          ElementDataCodec.decodeNullableString(
            json['textElementId'],
            fieldName: 'textElementId',
          ),
        ),
      );

  static const typeIdToken = ElementTypeId<SerialNumberData>('serial_number');

  final int number;
  final DrawColor color;
  final DrawColor fillColor;
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
    DrawColor? color,
    DrawColor? fillColor,
    FillStyle? fillStyle,
    double? fontSize,
    Object? fontFamily = _fontFamilyUnset,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    Object? textElementId = _textElementIdUnset,
  }) => SerialNumberData(
    number: _clampNonNegative(number ?? this.number),
    color: color ?? this.color,
    fillColor: fillColor ?? this.fillColor,
    fillStyle: fillStyle ?? this.fillStyle,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily == _fontFamilyUnset
        ? this.fontFamily
        : normalizeOptionalTrimmedString(fontFamily as String?),
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    textElementId: identical(textElementId, _textElementIdUnset)
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
    fontFamily: style.fontFamily,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    number: update.serialNumber,
    color: update.color,
    fillColor: update.fillColor,
    fillStyle: update.fillStyle,
    fontSize: update.fontSize,
    fontFamily: update.fontFamily ?? _fontFamilyUnset,
    strokeWidth: update.strokeWidth,
    strokeStyle: update.strokeStyle,
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

int _clampNonNegative(int value) => value < 0 ? 0 : value;
