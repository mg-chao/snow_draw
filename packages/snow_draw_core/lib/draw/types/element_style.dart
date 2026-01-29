import 'dart:ui';

import 'package:meta/meta.dart';

enum StrokeStyle { solid, dashed, dotted }

enum FillStyle { solid, line, crossLine }

enum ArrowType { straight, curved }

enum ArrowheadStyle {
  none,
  standard,
  triangle,
  square,
  circle,
  diamond,
  invertedTriangle,
  verticalLine,
}

enum TextHorizontalAlign { left, center, right }

enum TextVerticalAlign { top, center, bottom }

@immutable
class ElementStyleUpdate {
  const ElementStyleUpdate({
    this.color,
    this.fillColor,
    this.strokeWidth,
    this.strokeStyle,
    this.fillStyle,
    this.cornerRadius,
    this.arrowType,
    this.startArrowhead,
    this.endArrowhead,
    this.fontSize,
    this.fontFamily,
    this.textAlign,
    this.verticalAlign,
    this.textStrokeColor,
    this.textStrokeWidth,
  });

  final Color? color;
  final Color? fillColor;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final FillStyle? fillStyle;
  final double? cornerRadius;
  final ArrowType? arrowType;
  final ArrowheadStyle? startArrowhead;
  final ArrowheadStyle? endArrowhead;
  final double? fontSize;
  final String? fontFamily;
  final TextHorizontalAlign? textAlign;
  final TextVerticalAlign? verticalAlign;
  final Color? textStrokeColor;
  final double? textStrokeWidth;

  bool get isEmpty =>
      color == null &&
      fillColor == null &&
      strokeWidth == null &&
      strokeStyle == null &&
      fillStyle == null &&
      cornerRadius == null &&
      arrowType == null &&
      startArrowhead == null &&
      endArrowhead == null &&
      fontSize == null &&
      fontFamily == null &&
      textAlign == null &&
      verticalAlign == null &&
      textStrokeColor == null &&
      textStrokeWidth == null;

  ElementStyleUpdate copyWith({
    Color? color,
    Color? fillColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    String? fontFamily,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    Color? textStrokeColor,
    double? textStrokeWidth,
  }) => ElementStyleUpdate(
    color: color ?? this.color,
    fillColor: fillColor ?? this.fillColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    fillStyle: fillStyle ?? this.fillStyle,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    arrowType: arrowType ?? this.arrowType,
    startArrowhead: startArrowhead ?? this.startArrowhead,
    endArrowhead: endArrowhead ?? this.endArrowhead,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    textAlign: textAlign ?? this.textAlign,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    textStrokeColor: textStrokeColor ?? this.textStrokeColor,
    textStrokeWidth: textStrokeWidth ?? this.textStrokeWidth,
  );
}
