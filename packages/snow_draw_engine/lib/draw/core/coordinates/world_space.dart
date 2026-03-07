import '../../types/draw_point.dart';
import 'coordinate_space.dart';

class WorldSpace extends CoordinateSpace {
  const WorldSpace();

  @override
  double get rotation => 0;

  @override
  DrawPoint get origin => DrawPoint.zero;

  @override
  DrawPoint fromWorld(DrawPoint worldPoint) => worldPoint;

  @override
  DrawPoint toWorld(DrawPoint localPoint) => localPoint;
}
