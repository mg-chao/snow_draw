import 'dart:math' as math;

import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_hit_tester.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowHitTester path sampling integration', () {
    const tester = ArrowHitTester();

    test('hits a curved shaft sample point', () {
      final element = _buildCurvedArrowElement(rotation: 0);
      final sample = _resolveCurveSamplePoint(element: element, t: 0.5);

      expect(sample, isNotNull);
      final hit = tester.hitTest(element: element, position: sample!);

      expect(hit, isTrue);
    });

    test('hits a curved shaft sample point after element rotation', () {
      final element = _buildCurvedArrowElement(rotation: math.pi / 5);
      final sample = _resolveCurveSamplePoint(element: element, t: 0.5);

      expect(sample, isNotNull);
      final hit = tester.hitTest(element: element, position: sample!);

      expect(hit, isTrue);
    });

    test('misses points far from the curved shaft', () {
      final element = _buildCurvedArrowElement(rotation: 0);
      const miss = DrawPoint(x: 60, y: 95);

      final hit = tester.hitTest(element: element, position: miss);

      expect(hit, isFalse);
    });
  });
}

ElementState _buildCurvedArrowElement({required double rotation}) =>
    ElementState(
      id: 'curved-hit-arrow-$rotation',
      rect: const DrawRect(maxX: 120, maxY: 100),
      rotation: rotation,
      opacity: 1,
      zIndex: 0,
      data: const ArrowData(
        points: <DrawPoint>[
          DrawPoint(x: 0, y: 0.85),
          DrawPoint(x: 0.5, y: 0.1),
          DrawPoint(x: 1, y: 0.85),
        ],
        arrowType: ArrowType.curved,
        endArrowhead: ArrowheadStyle.none,
        strokeWidth: 3,
      ),
    );

DrawPoint? _resolveCurveSamplePoint({
  required ElementState element,
  required double t,
}) {
  final data = element.data as ArrowData;
  final points = _resolveRenderedWorldPoints(element: element, data: data);
  return ArrowGeometry.calculateCurveDrawPoint(
    points: points,
    segmentIndex: 0,
    t: t,
  );
}

List<DrawPoint> _resolveRenderedWorldPoints({
  required ElementState element,
  required ArrowData data,
}) {
  final unrotatedPoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  if (element.rotation == 0) {
    return unrotatedPoints;
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  return unrotatedPoints.map(space.toWorld).toList(growable: false);
}
