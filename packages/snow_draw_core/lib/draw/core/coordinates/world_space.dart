import '../../types/draw_point.dart';
import 'coordinate_space.dart';

class WorldSpace extends CoordinateSpace {
  const WorldSpace({this.rotation = 0.0, this.origin = DrawPoint.zero});
  @override
  final double rotation;

  @override
  final DrawPoint origin;

  @override
  DrawPoint fromWorld(DrawPoint worldPoint) => worldPoint;

  @override
  DrawPoint toWorld(DrawPoint localPoint) => localPoint;
}
