import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_core.dart' as core;

/// Encodes an engine [DrawPoint] into an arrow-core point tuple.
core.Point encodeArrowCorePoint(DrawPoint point) => <double>[point.x, point.y];

/// Encodes an iterable of engine points into arrow-core points.
List<core.Point> encodeArrowCorePoints(Iterable<DrawPoint> points) =>
    points.map(encodeArrowCorePoint).toList(growable: false);

/// Decodes an arrow-core point tuple into an engine [DrawPoint].
DrawPoint decodeArrowCorePoint(core.Point point) =>
    DrawPoint(x: point[0], y: point[1]);

/// Decodes an iterable of arrow-core points into engine points.
List<DrawPoint> decodeArrowCorePoints(Iterable<core.Point> points) =>
    points.map(decodeArrowCorePoint).toList(growable: false);

/// Encodes engine [ArrowheadStyle] into arrow-core arrowhead shape ids.
core.Arrowhead? encodeArrowCoreArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.none:
      return null;
    case ArrowheadStyle.standard:
      return 'arrow';
    case ArrowheadStyle.triangle:
      return 'triangle';
    case ArrowheadStyle.triangleOutline:
      return 'triangle_outline';
    case ArrowheadStyle.square:
      return 'square';
    case ArrowheadStyle.dot:
      return 'dot';
    case ArrowheadStyle.circle:
      return 'circle';
    case ArrowheadStyle.circleOutline:
      return 'circle_outline';
    case ArrowheadStyle.diamond:
      return 'diamond';
    case ArrowheadStyle.diamondOutline:
      return 'diamond_outline';
    case ArrowheadStyle.crowfootOne:
      return 'crowfoot_one';
    case ArrowheadStyle.crowfootMany:
      return 'crowfoot_many';
    case ArrowheadStyle.crowfootOneOrMany:
      return 'crowfoot_one_or_many';
    case ArrowheadStyle.invertedTriangle:
      return 'inverted_triangle';
    case ArrowheadStyle.verticalLine:
      return 'bar';
  }
}
