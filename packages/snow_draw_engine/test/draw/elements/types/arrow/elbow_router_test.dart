import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('elbow_router', () {
    test('routes unbound elbow arrow with horizontal-first common segment', () {
      final routed = routeElbowArrow(
        start: const DrawPoint(x: 0, y: 0),
        end: const DrawPoint(x: 250, y: 200),
        elementsById: const {},
        endArrowhead: ArrowheadStyle.standard,
      );

      expect(routed.points, const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 125, y: 0),
        DrawPoint(x: 125, y: 200),
        DrawPoint(x: 250, y: 200),
      ]);
    });
  });
}
