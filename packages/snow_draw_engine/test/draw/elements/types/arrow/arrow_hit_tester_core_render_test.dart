import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_hit_tester.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowHitTester arrowhead integration', () {
    const tester = ArrowHitTester();

    test('core-rendered standard arrowhead is hittable', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.standard);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 90, y: 13),
      );

      expect(hit, isTrue);
    });

    test('core-rendered circle arrowhead is hittable', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.circle);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 100, y: 10),
      );

      expect(hit, isTrue);
    });

    test('core-rendered circle arrowhead interior is hittable', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.circle);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 94, y: 10),
      );

      expect(hit, isTrue);
    });

    test('core-rendered triangle arrowhead interior is hittable', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.triangle);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 92, y: 10),
      );

      expect(hit, isTrue);
    });

    test('core-rendered square arrowhead is hittable', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.square);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 96, y: 16),
      );

      expect(hit, isTrue);
    });

    test('no arrowhead does not hit far from shaft', () {
      final element = _buildArrowElement(endArrowhead: ArrowheadStyle.none);

      final hit = tester.hitTest(
        element: element,
        position: const DrawPoint(x: 90, y: 16),
      );

      expect(hit, isFalse);
    });

    test(
      'triangle outline arrowhead interior does not hit trimmed shaft segment',
      () {
        final element = _buildArrowElement(
          endArrowhead: ArrowheadStyle.triangleOutline,
          strokeWidth: 4,
          width: 120,
        );

        final hit = tester.hitTest(
          element: element,
          position: const DrawPoint(x: 100, y: 10),
        );

        expect(hit, isFalse);
      },
    );
  });
}

ElementState _buildArrowElement({
  required ArrowheadStyle endArrowhead,
  double strokeWidth = 2,
  double width = 100,
}) => ElementState(
  id: 'arrow-hit-test',
  rect: DrawRect(maxX: width, maxY: 20),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: ArrowData(
    points: const <DrawPoint>[DrawPoint(y: 0.5, x: 0), DrawPoint(x: 1, y: 0.5)],
    endArrowhead: endArrowhead,
    strokeWidth: strokeWidth,
  ),
);
