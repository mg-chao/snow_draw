import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_geometry_adapter.dart';
import 'arrow_like_data.dart';

/// Result of resolving max label dimensions for a bound arrow text block.
typedef ArrowBoundTextConstraints = ({double maxWidth, double maxHeight});

/// Result of expanding linear-element bounds to include bound text.
typedef LinearBoundsWithBoundText = ({DrawRect rect, DrawPoint center});

/// Computes a stable container dimension for bound arrow text.
///
/// This delegates to the integrated arrow core label defaults and clamping
/// rules.
double computeArrowContainerDimensionForBoundText(
  double dimension, {
  core.ArrowLabelLayoutOptions? options,
}) => core.computeArrowContainerDimensionForBoundText(
  dimension,
  options: options,
);

/// Computes max width and height constraints for bound arrow text.
ArrowBoundTextConstraints computeArrowBoundTextConstraints({
  required double containerWidth,
  required double containerHeight,
  required double fontSize,
  required double boundTextHeight,
  core.ArrowLabelLayoutOptions? options,
}) => (
  maxWidth: core.getArrowBoundTextMaxWidth(
    containerWidth,
    fontSize,
    options: options,
  ),
  maxHeight: core.getArrowBoundTextMaxHeight(
    containerHeight,
    boundTextHeight,
    options: options,
  ),
);

/// Resolves the label anchor point for a world-space arrow polyline.
DrawPoint? resolveArrowLabelAnchorPoint({
  required List<DrawPoint> worldPoints,
  DrawPoint? middleSegmentMidPoint,
}) {
  final anchor = core.getArrowLabelAnchorPoint(
    core.ArrowLabelAnchorInput(
      globalPoints: _toCorePoints(worldPoints),
      middleSegmentMidPoint: middleSegmentMidPoint == null
          ? null
          : <double>[middleSegmentMidPoint.x, middleSegmentMidPoint.y],
    ),
  );
  if (anchor == null) {
    return null;
  }
  return DrawPoint(x: anchor[0], y: anchor[1]);
}

/// Resolves the label anchor for an arrow element snapshot.
DrawPoint? resolveArrowLabelAnchorPointForElement({
  required ElementState element,
  required ArrowLikeData data,
  DrawPoint? middleSegmentMidPoint,
}) => resolveArrowLabelAnchorPoint(
  worldPoints: resolveArrowWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ),
  middleSegmentMidPoint: middleSegmentMidPoint,
);

/// Resolves top-left label position for world-space arrow points.
DrawPoint? resolveArrowBoundTextPosition({
  required List<DrawPoint> worldPoints,
  required double boundTextWidth,
  required double boundTextHeight,
  DrawPoint? middleSegmentMidPoint,
}) {
  final position = core.getArrowBoundTextPosition(
    core.ArrowBoundTextPositionInput(
      globalPoints: _toCorePoints(worldPoints),
      boundTextWidth: boundTextWidth,
      boundTextHeight: boundTextHeight,
      middleSegmentMidPoint: middleSegmentMidPoint == null
          ? null
          : <double>[middleSegmentMidPoint.x, middleSegmentMidPoint.y],
    ),
  );
  if (position == null) {
    return null;
  }
  return DrawPoint(x: position.x, y: position.y);
}

/// Resolves top-left label position for an arrow element snapshot.
DrawPoint? resolveArrowBoundTextPositionForElement({
  required ElementState element,
  required ArrowLikeData data,
  required double boundTextWidth,
  required double boundTextHeight,
  DrawPoint? middleSegmentMidPoint,
}) => resolveArrowBoundTextPosition(
  worldPoints: resolveArrowWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ),
  boundTextWidth: boundTextWidth,
  boundTextHeight: boundTextHeight,
  middleSegmentMidPoint: middleSegmentMidPoint,
);

/// Expands linear bounds to include bound text using core parity logic.
LinearBoundsWithBoundText resolveLinearBoundsWithBoundText({
  required DrawRect elementBounds,
  required DrawRect boundTextBounds,
  required double angle,
}) {
  final bounds = core.getLinearElementBoundsWithBoundText(
    core.LinearElementBoundsWithBoundTextInput(
      elementBounds: <double>[
        elementBounds.minX,
        elementBounds.minY,
        elementBounds.maxX,
        elementBounds.maxY,
      ],
      boundTextBounds: <double>[
        boundTextBounds.minX,
        boundTextBounds.minY,
        boundTextBounds.maxX,
        boundTextBounds.maxY,
      ],
      angle: angle,
    ),
  );
  return (
    rect: DrawRect(
      minX: bounds[0],
      minY: bounds[1],
      maxX: bounds[2],
      maxY: bounds[3],
    ),
    center: DrawPoint(x: bounds[4], y: bounds[5]),
  );
}

List<core.Point> _toCorePoints(List<DrawPoint> points) => List<core.Point>.of(
  points.map((point) => <double>[point.x, point.y]),
  growable: false,
);
