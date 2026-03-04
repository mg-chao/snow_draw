import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowGeometry core elbow integration', () {
    test('generateElbowPathData returns rounded-corner path commands', () {
      final path = ArrowGeometry.generateElbowPathData(
        points: const <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 100, y: 0),
          DrawPoint(x: 100, y: 100),
        ],
      );

      expect(path, 'M 0 0 L 84 0 Q 100 0, 100 16 L 100 100');
    });

    test('generateElbowPathData handles a single point', () {
      final path = ArrowGeometry.generateElbowPathData(
        points: const <DrawPoint>[DrawPoint(x: 12.5, y: -3.25)],
      );

      expect(path, 'M 12.5 -3.25');
    });
  });
}
