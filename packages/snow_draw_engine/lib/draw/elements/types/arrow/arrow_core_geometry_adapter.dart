import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_core_codec.dart';

/// Result of recomputing element geometry from edited arrow points.
typedef ArrowGeometryUpdate = ({
  DrawRect rect,
  List<DrawPoint> normalizedPoints,
});

/// Cached layout payload for 2-point arrow-like elements.
///
/// The rect is in world space and [normalizedPoints] are rect-normalized.
class ArrowTwoPointLayout {
  const ArrowTwoPointLayout({
    required this.rect,
    required this.normalizedPoints,
  });

  final DrawRect rect;
  final List<DrawPoint> normalizedPoints;
}

List<DrawPoint> resolveArrowLocalPoints({
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) {
  final localPoints = core.denormalizeRectPoints(
    rect: <double>[0, 0, rect.width, rect.height],
    normalizedPoints: encodeArrowCorePoints(normalizedPoints),
  );
  return _decodeWithPressure(points: localPoints, source: normalizedPoints);
}

List<DrawPoint> resolveArrowWorldPoints({
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) {
  final worldPoints = core.denormalizeRectPoints(
    rect: _toBounds(rect),
    normalizedPoints: encodeArrowCorePoints(normalizedPoints),
  );
  return _decodeWithPressure(points: worldPoints, source: normalizedPoints);
}

List<DrawPoint> normalizeArrowPoints({
  required List<DrawPoint> worldPoints,
  required DrawRect rect,
}) {
  final normalized = core.normalizeRectPoints(
    rect: _toBounds(rect),
    worldPoints: encodeArrowCorePoints(worldPoints),
  );
  return _decodeWithPressure(points: normalized, source: worldPoints);
}

DrawRect calculateArrowPathBoundsViaCore({
  required List<DrawPoint> worldPoints,
  required ArrowType arrowType,
}) {
  final bounds = core.calculateArrowPathBounds(
    points: encodeArrowCorePoints(worldPoints),
    curved: arrowType == ArrowType.curved,
  );
  return DrawRect(
    minX: bounds[0],
    minY: bounds[1],
    maxX: bounds[2],
    maxY: bounds[3],
  );
}

/// Computes rect + normalized points for a 2-point arrow fast path.
ArrowTwoPointLayout computeArrowTwoPointLayout({
  required DrawPoint first,
  required DrawPoint second,
}) {
  final layout = core.computeTwoPointRectNormalizedPoints(
    first: <double>[first.x, first.y],
    second: <double>[second.x, second.y],
  );
  return ArrowTwoPointLayout(
    rect: DrawRect(
      minX: layout.rect[0],
      minY: layout.rect[1],
      maxX: layout.rect[2],
      maxY: layout.rect[3],
    ),
    normalizedPoints: List<DrawPoint>.unmodifiable(<DrawPoint>[
      DrawPoint(
        x: layout.normalizedPoints[0][0],
        y: layout.normalizedPoints[0][1],
        pressure: first.pressure,
      ),
      DrawPoint(
        x: layout.normalizedPoints[1][0],
        y: layout.normalizedPoints[1][1],
        pressure: second.pressure,
      ),
    ]),
  );
}

/// Recomputes rect + normalized points after arrow local points changed.
ArrowGeometryUpdate resolveArrowGeometryUpdate({
  required List<DrawPoint> localPoints,
  required DrawRect oldRect,
  required double rotation,
  required ArrowType arrowType,
}) {
  final layout = core.computeRotatedRectAndLocalPoints(
    localPoints: encodeArrowCorePoints(localPoints),
    oldRect: <double>[oldRect.minX, oldRect.minY, oldRect.maxX, oldRect.maxY],
    rotation: rotation,
    curved: arrowType == ArrowType.curved,
  );
  final rect = DrawRect(
    minX: layout.rect[0],
    minY: layout.rect[1],
    maxX: layout.rect[2],
    maxY: layout.rect[3],
  );
  final nextLocalPoints = _decodeWithPressure(
    points: layout.localPoints,
    source: localPoints,
  );
  return (
    rect: rect,
    normalizedPoints: normalizeArrowPoints(
      worldPoints: nextLocalPoints,
      rect: rect,
    ),
  );
}

List<double> _toBounds(DrawRect rect) => <double>[
  rect.minX,
  rect.minY,
  rect.maxX,
  rect.maxY,
];

List<DrawPoint> _decodeWithPressure({
  required List<core.Point> points,
  required List<DrawPoint> source,
}) {
  if (source.isEmpty) {
    return decodeArrowCorePoints(points);
  }
  return List<DrawPoint>.generate(points.length, (index) {
    final sourcePoint =
        source[index < source.length ? index : source.length - 1];
    final point = points[index];
    return DrawPoint(x: point[0], y: point[1], pressure: sourcePoint.pressure);
  }, growable: false);
}
