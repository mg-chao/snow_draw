import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

/// Represents a style property value that may differ
/// across multiple selected elements.
///
/// When multiple elements are selected and they have different
/// values for a property,
/// [isMixed] is true and [value] is null. This allows the UI
/// to display "Mixed" or
/// a placeholder instead of showing an arbitrary value from one element.
///
/// When [isMixed] is false, [value] contains the actual
/// property value (either from
/// a single selected element or a common value shared by
///  all selected elements).
@immutable
class MixedValue<T> {
  const MixedValue({required this.value, required this.isMixed});

  final T? value;
  final bool isMixed;

  T valueOr(T fallback) => value ?? fallback;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixedValue<T> &&
          other.value == value &&
          other.isMixed == isMixed;

  @override
  int get hashCode => Object.hash(value, isMixed);
}

/// Resolved style values for rectangle elements, supporting multi-selection.
///
/// Each property is wrapped in [MixedValue] to handle cases where multiple
/// selected rectangles have different values for that property.
@immutable
class RectangleStyleValues {
  const RectangleStyleValues({
    required this.color,
    required this.fillColor,
    required this.strokeStyle,
    required this.fillStyle,
    required this.strokeWidth,
    required this.cornerRadius,
    required this.opacity,
  });

  final MixedValue<Color> color;
  final MixedValue<Color> fillColor;
  final MixedValue<StrokeStyle> strokeStyle;
  final MixedValue<FillStyle> fillStyle;
  final MixedValue<double> strokeWidth;
  final MixedValue<double> cornerRadius;
  final MixedValue<double> opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RectangleStyleValues &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.strokeStyle == strokeStyle &&
          other.fillStyle == fillStyle &&
          other.strokeWidth == strokeWidth &&
          other.cornerRadius == cornerRadius &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    color,
    fillColor,
    strokeStyle,
    fillStyle,
    strokeWidth,
    cornerRadius,
    opacity,
  );
}

/// Resolved style values for text elements, supporting multi-selection.
///
/// Each property is wrapped in [MixedValue] to handle cases where multiple
/// selected text elements have different values for that property.
@immutable
class TextStyleValues {
  const TextStyleValues({
    required this.color,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.verticalAlign,
    required this.fillColor,
    required this.fillStyle,
    required this.textStrokeColor,
    required this.textStrokeWidth,
    required this.cornerRadius,
    required this.opacity,
  });

  final MixedValue<Color> color;
  final MixedValue<double> fontSize;
  final MixedValue<String> fontFamily;
  final MixedValue<TextHorizontalAlign> horizontalAlign;
  final MixedValue<TextVerticalAlign> verticalAlign;
  final MixedValue<Color> fillColor;
  final MixedValue<FillStyle> fillStyle;
  final MixedValue<Color> textStrokeColor;
  final MixedValue<double> textStrokeWidth;
  final MixedValue<double> cornerRadius;
  final MixedValue<double> opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextStyleValues &&
          other.color == color &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.verticalAlign == verticalAlign &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.textStrokeColor == textStrokeColor &&
          other.textStrokeWidth == textStrokeWidth &&
          other.cornerRadius == cornerRadius &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    color,
    fontSize,
    fontFamily,
    horizontalAlign,
    verticalAlign,
    fillColor,
    fillStyle,
    textStrokeColor,
    textStrokeWidth,
    cornerRadius,
    opacity,
  );
}

/// Resolved style values for arrow elements, supporting multi-selection.
@immutable
class ArrowStyleValues {
  const ArrowStyleValues({
    required this.color,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.arrowType,
    required this.startArrowhead,
    required this.endArrowhead,
    required this.opacity,
  });

  final MixedValue<Color> color;
  final MixedValue<double> strokeWidth;
  final MixedValue<StrokeStyle> strokeStyle;
  final MixedValue<ArrowType> arrowType;
  final MixedValue<ArrowheadStyle> startArrowhead;
  final MixedValue<ArrowheadStyle> endArrowhead;
  final MixedValue<double> opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowStyleValues &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.arrowType == arrowType &&
          other.startArrowhead == startArrowhead &&
          other.endArrowhead == endArrowhead &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    color,
    strokeWidth,
    strokeStyle,
    arrowType,
    startArrowhead,
    endArrowhead,
    opacity,
  );
}

/// Resolved style values for line elements, supporting multi-selection.
@immutable
class LineStyleValues {
  const LineStyleValues({
    required this.color,
    required this.fillColor,
    required this.fillStyle,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.opacity,
  });

  final MixedValue<Color> color;
  final MixedValue<Color> fillColor;
  final MixedValue<FillStyle> fillStyle;
  final MixedValue<double> strokeWidth;
  final MixedValue<StrokeStyle> strokeStyle;
  final MixedValue<double> opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineStyleValues &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    color,
    fillColor,
    fillStyle,
    strokeWidth,
    strokeStyle,
    opacity,
  );
}

/// Resolved style values for serial number elements, supporting
/// multi-selection.
@immutable
class SerialNumberStyleValues {
  const SerialNumberStyleValues({
    required this.color,
    required this.fillColor,
    required this.fillStyle,
    required this.fontSize,
    required this.fontFamily,
    required this.number,
    required this.opacity,
  });

  final MixedValue<Color> color;
  final MixedValue<Color> fillColor;
  final MixedValue<FillStyle> fillStyle;
  final MixedValue<double> fontSize;
  final MixedValue<String> fontFamily;
  final MixedValue<int> number;
  final MixedValue<double> opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialNumberStyleValues &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.number == number &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    color,
    fillColor,
    fillStyle,
    fontSize,
    fontFamily,
    number,
    opacity,
  );
}

@immutable
class StyleToolbarState {
  const StyleToolbarState({
    required this.rectangleStyle,
    required this.arrowStyle,
    required this.lineStyle,
    required this.freeDrawStyle,
    required this.textStyle,
    required this.serialNumberStyle,
    required this.styleValues,
    required this.arrowStyleValues,
    required this.lineStyleValues,
    required this.freeDrawStyleValues,
    required this.textStyleValues,
    required this.serialNumberStyleValues,
    required this.hasSelection,
    required this.hasSelectedRectangles,
    required this.hasSelectedArrows,
    required this.hasSelectedLines,
    required this.hasSelectedFreeDraws,
    required this.hasSelectedTexts,
    required this.hasSelectedSerialNumbers,
  });

  final ElementStyleConfig rectangleStyle;
  final ElementStyleConfig arrowStyle;
  final ElementStyleConfig lineStyle;
  final ElementStyleConfig freeDrawStyle;
  final ElementStyleConfig textStyle;
  final ElementStyleConfig serialNumberStyle;
  final RectangleStyleValues styleValues;
  final ArrowStyleValues arrowStyleValues;
  final LineStyleValues lineStyleValues;
  final LineStyleValues freeDrawStyleValues;
  final TextStyleValues textStyleValues;
  final SerialNumberStyleValues serialNumberStyleValues;
  final bool hasSelection;
  final bool hasSelectedRectangles;
  final bool hasSelectedArrows;
  final bool hasSelectedLines;
  final bool hasSelectedFreeDraws;
  final bool hasSelectedTexts;
  final bool hasSelectedSerialNumbers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StyleToolbarState &&
          other.rectangleStyle == rectangleStyle &&
          other.arrowStyle == arrowStyle &&
          other.lineStyle == lineStyle &&
          other.freeDrawStyle == freeDrawStyle &&
          other.textStyle == textStyle &&
          other.serialNumberStyle == serialNumberStyle &&
          other.styleValues == styleValues &&
          other.arrowStyleValues == arrowStyleValues &&
          other.lineStyleValues == lineStyleValues &&
          other.freeDrawStyleValues == freeDrawStyleValues &&
          other.textStyleValues == textStyleValues &&
          other.serialNumberStyleValues == serialNumberStyleValues &&
          other.hasSelection == hasSelection &&
          other.hasSelectedRectangles == hasSelectedRectangles &&
          other.hasSelectedArrows == hasSelectedArrows &&
          other.hasSelectedLines == hasSelectedLines &&
          other.hasSelectedFreeDraws == hasSelectedFreeDraws &&
          other.hasSelectedTexts == hasSelectedTexts &&
          other.hasSelectedSerialNumbers == hasSelectedSerialNumbers;

  @override
  int get hashCode => Object.hash(
    rectangleStyle,
    arrowStyle,
    lineStyle,
    freeDrawStyle,
    textStyle,
    serialNumberStyle,
    styleValues,
    arrowStyleValues,
    lineStyleValues,
    freeDrawStyleValues,
    textStyleValues,
    serialNumberStyleValues,
    hasSelection,
    hasSelectedRectangles,
    hasSelectedArrows,
    hasSelectedLines,
    hasSelectedFreeDraws,
    hasSelectedTexts,
    hasSelectedSerialNumbers,
  );
}
