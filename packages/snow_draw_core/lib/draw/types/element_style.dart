import 'package:meta/meta.dart';

import 'draw_color.dart';

enum StrokeStyle { solid, dashed, dotted }

enum FillStyle { solid, line, crossLine }

enum HighlightShape { rectangle, ellipse }

enum CanvasFilterType { mosaic, gaussianBlur, grayscale, inversion }

enum ArrowType { straight, curved, elbow }

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
    this.highlightShape,
    this.filterType,
    this.filterStrength,
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
    this.serialNumber,
  });

  final DrawColor? color;
  final DrawColor? fillColor;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final FillStyle? fillStyle;
  final HighlightShape? highlightShape;
  final CanvasFilterType? filterType;
  final double? filterStrength;
  final double? cornerRadius;
  final ArrowType? arrowType;
  final ArrowheadStyle? startArrowhead;
  final ArrowheadStyle? endArrowhead;
  final double? fontSize;
  final String? fontFamily;
  final TextHorizontalAlign? textAlign;
  final TextVerticalAlign? verticalAlign;
  final DrawColor? textStrokeColor;
  final double? textStrokeWidth;
  final int? serialNumber;

  bool get isEmpty =>
      color == null &&
      fillColor == null &&
      strokeWidth == null &&
      strokeStyle == null &&
      fillStyle == null &&
      highlightShape == null &&
      filterType == null &&
      filterStrength == null &&
      cornerRadius == null &&
      arrowType == null &&
      startArrowhead == null &&
      endArrowhead == null &&
      fontSize == null &&
      fontFamily == null &&
      textAlign == null &&
      verticalAlign == null &&
      textStrokeColor == null &&
      textStrokeWidth == null &&
      serialNumber == null;
}
