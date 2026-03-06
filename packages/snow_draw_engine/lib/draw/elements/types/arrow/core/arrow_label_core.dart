import 'arrow_geom.dart';
import 'arrow_types.dart';

class ArrowLabelLayoutOptions {
  const ArrowLabelLayoutOptions({
    this.textPadding,
    this.widthFraction,
    this.fontSizeToMinWidthRatio,
    this.paddingMultiplier,
  });

  final double? textPadding;
  final double? widthFraction;
  final double? fontSizeToMinWidthRatio;
  final double? paddingMultiplier;
}

class _ResolvedArrowLabelLayoutOptions {
  const _ResolvedArrowLabelLayoutOptions({
    required this.textPadding,
    required this.widthFraction,
    required this.fontSizeToMinWidthRatio,
    required this.paddingMultiplier,
  });

  final double textPadding;
  final double widthFraction;
  final double fontSizeToMinWidthRatio;
  final double paddingMultiplier;
}

const ArrowLabelLayoutOptions arrowLabelLayoutDefaults =
    ArrowLabelLayoutOptions(
      textPadding: 5,
      widthFraction: 0.7,
      fontSizeToMinWidthRatio: 11,
      paddingMultiplier: 8,
    );
// ignore: constant_identifier_names
const ArrowLabelLayoutOptions ARROW_LABEL_LAYOUT_DEFAULTS =
    arrowLabelLayoutDefaults;

const _resolvedDefaults = _ResolvedArrowLabelLayoutOptions(
  textPadding: 5,
  widthFraction: 0.7,
  fontSizeToMinWidthRatio: 11,
  paddingMultiplier: 8,
);

_ResolvedArrowLabelLayoutOptions _resolveArrowLabelLayoutOptions(
  ArrowLabelLayoutOptions? options,
) {
  var textPadding = _resolvedDefaults.textPadding;
  var widthFraction = _resolvedDefaults.widthFraction;
  var fontSizeToMinWidthRatio = _resolvedDefaults.fontSizeToMinWidthRatio;
  var paddingMultiplier = _resolvedDefaults.paddingMultiplier;

  if (options?.textPadding != null && options!.textPadding!.isFinite) {
    textPadding = options.textPadding!.clamp(0, double.infinity);
  }
  if (options?.widthFraction != null && options!.widthFraction!.isFinite) {
    widthFraction = options.widthFraction!.clamp(0, double.infinity);
  }
  if (options?.fontSizeToMinWidthRatio != null &&
      options!.fontSizeToMinWidthRatio!.isFinite) {
    fontSizeToMinWidthRatio = options.fontSizeToMinWidthRatio!.clamp(
      0,
      double.infinity,
    );
  }
  if (options?.paddingMultiplier != null &&
      options!.paddingMultiplier!.isFinite) {
    paddingMultiplier = options.paddingMultiplier!.clamp(0, double.infinity);
  }

  return _ResolvedArrowLabelLayoutOptions(
    textPadding: textPadding,
    widthFraction: widthFraction,
    fontSizeToMinWidthRatio: fontSizeToMinWidthRatio,
    paddingMultiplier: paddingMultiplier,
  );
}

double computeArrowContainerDimensionForBoundText(
  double dimension, {
  ArrowLabelLayoutOptions? options,
}) {
  final resolved = _resolveArrowLabelLayoutOptions(options);
  final baseDimension = dimension.isFinite ? dimension.ceilToDouble() : 0;
  final padding = resolved.textPadding * 2;
  return baseDimension + padding * resolved.paddingMultiplier;
}

double getArrowBoundTextMaxWidth(
  double containerWidth,
  double fontSize, {
  ArrowLabelLayoutOptions? options,
}) {
  final resolved = _resolveArrowLabelLayoutOptions(options);
  final width = containerWidth.isFinite ? containerWidth : 0;
  final normalizedFontSize = fontSize.isFinite ? fontSize : 0;
  final minWidth = normalizedFontSize * resolved.fontSizeToMinWidthRatio;
  return width * resolved.widthFraction > minWidth
      ? width * resolved.widthFraction
      : minWidth;
}

double getArrowBoundTextMaxHeight(
  double containerHeight,
  double boundTextHeight, {
  ArrowLabelLayoutOptions? options,
}) {
  final resolved = _resolveArrowLabelLayoutOptions(options);
  final height = containerHeight.isFinite ? containerHeight : 0.0;
  final normalizedBoundTextHeight = boundTextHeight.isFinite
      ? boundTextHeight
      : 0.0;
  final effectiveHeight =
      height - resolved.textPadding * resolved.paddingMultiplier * 2;
  if (effectiveHeight <= 0) {
    return normalizedBoundTextHeight;
  }
  return height;
}

class ArrowBoundTextPositionInput {
  const ArrowBoundTextPositionInput({
    required this.globalPoints,
    required this.boundTextWidth,
    required this.boundTextHeight,
    this.middleSegmentMidPoint,
  });

  final List<Point> globalPoints;
  final double boundTextWidth;
  final double boundTextHeight;
  final Point? middleSegmentMidPoint;
}

class ArrowLabelAnchorInput {
  const ArrowLabelAnchorInput({
    required this.globalPoints,
    this.middleSegmentMidPoint,
  });

  final List<Point> globalPoints;
  final Point? middleSegmentMidPoint;
}

Point? getArrowLabelAnchorPoint(ArrowLabelAnchorInput input) {
  final globalPoints = input.globalPoints;
  if (globalPoints.length < 2) {
    return null;
  }

  if (globalPoints.length.isOdd) {
    final midPoint = globalPoints[globalPoints.length ~/ 2];
    return [midPoint[0], midPoint[1]];
  }

  final middleSegmentIndex = globalPoints.length ~/ 2 - 1;
  final start = globalPoints[middleSegmentIndex];
  final end = globalPoints[middleSegmentIndex + 1];

  final midpoint =
      input.middleSegmentMidPoint ??
      <double>[(start[0] + end[0]) / 2, (start[1] + end[1]) / 2];
  return [midpoint[0], midpoint[1]];
}

({double x, double y})? getArrowBoundTextPosition(
  ArrowBoundTextPositionInput input,
) {
  final width = input.boundTextWidth.isFinite ? input.boundTextWidth : 0;
  final height = input.boundTextHeight.isFinite ? input.boundTextHeight : 0;
  final anchor = getArrowLabelAnchorPoint(
    ArrowLabelAnchorInput(
      globalPoints: input.globalPoints,
      middleSegmentMidPoint: input.middleSegmentMidPoint,
    ),
  );
  if (anchor == null) {
    return null;
  }

  return (x: anchor[0] - width / 2, y: anchor[1] - height / 2);
}

class LinearElementBoundsWithBoundTextInput {
  const LinearElementBoundsWithBoundTextInput({
    required this.elementBounds,
    required this.boundTextBounds,
    required this.angle,
  });

  final Bounds elementBounds;
  final Bounds boundTextBounds;
  final double angle;
}

List<double> getLinearElementBoundsWithBoundText(
  LinearElementBoundsWithBoundTextInput input,
) {
  var x1 = input.elementBounds[0];
  var y1 = input.elementBounds[1];
  var x2 = input.elementBounds[2];
  var y2 = input.elementBounds[3];

  final boundTextX1 = input.boundTextBounds[0];
  final boundTextY1 = input.boundTextBounds[1];
  final boundTextX2 = input.boundTextBounds[2];
  final boundTextY2 = input.boundTextBounds[3];

  final cx = (x1 + x2) / 2;
  final cy = (y1 + y2) / 2;
  final centerPoint = <double>[cx, cy];
  final angle = input.angle.isFinite ? input.angle : 0.0;

  final topLeftRotatedPoint = rotatePoint(<double>[x1, y1], centerPoint, angle);
  final topRightRotatedPoint = rotatePoint(
    <double>[x2, y1],
    centerPoint,
    angle,
  );

  final counterRotateBoundTextTopLeft = rotatePoint(
    <double>[boundTextX1, boundTextY1],
    centerPoint,
    -angle,
  );
  final counterRotateBoundTextTopRight = rotatePoint(
    <double>[boundTextX2, boundTextY1],
    centerPoint,
    -angle,
  );
  final counterRotateBoundTextBottomLeft = rotatePoint(
    <double>[boundTextX1, boundTextY2],
    centerPoint,
    -angle,
  );
  final counterRotateBoundTextBottomRight = rotatePoint(
    <double>[boundTextX2, boundTextY2],
    centerPoint,
    -angle,
  );

  if (topLeftRotatedPoint[0] < topRightRotatedPoint[0] &&
      topLeftRotatedPoint[1] >= topRightRotatedPoint[1]) {
    x1 = x1 < counterRotateBoundTextBottomLeft[0]
        ? x1
        : counterRotateBoundTextBottomLeft[0];
    x2 = x2 > counterRotateBoundTextTopRight[0]
        ? (x2 > counterRotateBoundTextBottomRight[0]
              ? x2
              : counterRotateBoundTextBottomRight[0])
        : (counterRotateBoundTextTopRight[0] >
                  counterRotateBoundTextBottomRight[0]
              ? counterRotateBoundTextTopRight[0]
              : counterRotateBoundTextBottomRight[0]);
    y1 = y1 < counterRotateBoundTextTopLeft[1]
        ? y1
        : counterRotateBoundTextTopLeft[1];
    y2 = y2 > counterRotateBoundTextBottomRight[1]
        ? y2
        : counterRotateBoundTextBottomRight[1];
  } else if (topLeftRotatedPoint[0] >= topRightRotatedPoint[0] &&
      topLeftRotatedPoint[1] > topRightRotatedPoint[1]) {
    x1 = x1 < counterRotateBoundTextBottomRight[0]
        ? x1
        : counterRotateBoundTextBottomRight[0];
    final candidateX2 =
        counterRotateBoundTextTopLeft[0] > counterRotateBoundTextTopRight[0]
        ? counterRotateBoundTextTopLeft[0]
        : counterRotateBoundTextTopRight[0];
    x2 = x2 > candidateX2 ? x2 : candidateX2;
    y1 = y1 < counterRotateBoundTextBottomLeft[1]
        ? y1
        : counterRotateBoundTextBottomLeft[1];
    y2 = y2 > counterRotateBoundTextTopRight[1]
        ? y2
        : counterRotateBoundTextTopRight[1];
  } else if (topLeftRotatedPoint[0] >= topRightRotatedPoint[0]) {
    x1 = x1 < counterRotateBoundTextTopRight[0]
        ? x1
        : counterRotateBoundTextTopRight[0];
    x2 = x2 > counterRotateBoundTextBottomLeft[0]
        ? x2
        : counterRotateBoundTextBottomLeft[0];
    y1 = y1 < counterRotateBoundTextBottomRight[1]
        ? y1
        : counterRotateBoundTextBottomRight[1];
    y2 = y2 > counterRotateBoundTextTopLeft[1]
        ? y2
        : counterRotateBoundTextTopLeft[1];
  } else if (topLeftRotatedPoint[1] <= topRightRotatedPoint[1]) {
    final candidateX1 =
        counterRotateBoundTextTopRight[0] < counterRotateBoundTextTopLeft[0]
        ? counterRotateBoundTextTopRight[0]
        : counterRotateBoundTextTopLeft[0];
    x1 = x1 < candidateX1 ? x1 : candidateX1;
    x2 = x2 > counterRotateBoundTextBottomRight[0]
        ? x2
        : counterRotateBoundTextBottomRight[0];
    y1 = y1 < counterRotateBoundTextTopRight[1]
        ? y1
        : counterRotateBoundTextTopRight[1];
    y2 = y2 > counterRotateBoundTextBottomLeft[1]
        ? y2
        : counterRotateBoundTextBottomLeft[1];
  }

  return <double>[x1, y1, x2, y2, cx, cy];
}
