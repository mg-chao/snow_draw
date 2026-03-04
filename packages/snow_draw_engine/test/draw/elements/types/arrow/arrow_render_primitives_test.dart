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

    test('resolves square fallback into filled polygon primitive', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.square,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
      );

      final polygon = primitives.whereType<ArrowheadPolygonPrimitiveData>();
      expect(polygon, hasLength(1));
      expect(polygon.single.fillMode, ArrowheadPrimitiveFillMode.stroke);
      expect(polygon.single.points.length, 4);
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

    test('resolves inverted triangle fallback with opposite heading', () {
      final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
        points: points,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.invertedTriangle,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
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
