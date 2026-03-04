import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowRenderPrimitives', () {
    const points = <DrawPoint>[
      DrawPoint(x: 0, y: 10),
      DrawPoint(x: 100, y: 10),
    ];

    test('resolves core triangle into filled polygon primitive', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.triangle,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
      );

      final polygon = primitives.whereType<ArrowheadPolygonPrimitiveData>();
      expect(polygon, hasLength(1));
      expect(polygon.single.fillMode, ArrowheadPrimitiveFillMode.stroke);
      expect(polygon.single.points.length, greaterThanOrEqualTo(3));
    });

    test('resolves core square into filled polygon primitive', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.square,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
        directionOverride: const DrawPoint(x: -1, y: 0),
      );

      final polygon = primitives.whereType<ArrowheadPolygonPrimitiveData>();
      expect(polygon, hasLength(1));
      expect(polygon.single.fillMode, ArrowheadPrimitiveFillMode.stroke);
      expect(polygon.single.points.length, 4);
      final maxX = polygon.single.points
          .map((point) => point.x)
          .reduce((left, right) => left > right ? left : right);
      expect(maxX, lessThanOrEqualTo(points.last.x + 1e-6));
    });

    test('resolves circle into filled circle primitive', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.circle,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
      );

      final circles = primitives.whereType<ArrowheadCirclePrimitiveData>();
      expect(circles, hasLength(1));
      expect(circles.single.fillMode, ArrowheadPrimitiveFillMode.stroke);
      expect(circles.single.radius, greaterThan(0));
      expect(circles.single.center.x, lessThanOrEqualTo(points.last.x));
    });

    test('resolves core inverted triangle with opposite heading', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.invertedTriangle,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
        directionOverride: const DrawPoint(x: -1, y: 0),
      );

      final polygon = primitives.whereType<ArrowheadPolygonPrimitiveData>();
      expect(polygon, hasLength(1));
      expect(
        polygon.single.points.any((point) => point.x > points.last.x),
        isTrue,
      );
    });
  });
}
