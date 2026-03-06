import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_render_core custom arrowheads', () {
    const arrowPoints = <Point>[
      <double>[0, 10],
      <double>[100, 10],
    ];
    const curveOps = <CurvePathOp>[
      CurvePathOp(op: 'move', data: <double>[0, 10]),
      CurvePathOp(op: 'bcurveTo', data: <double>[33, 10, 66, 10, 100, 10]),
    ];

    test('renders square arrowhead as polygon primitive', () {
      final primitives = getArrowheadRenderPrimitives(
        const ArrowheadRenderPrimitivesInput(
          arrowPoints: arrowPoints,
          strokeWidth: 2,
          curveOps: curveOps,
          position: arrowEndpointPositionEnd,
          arrowhead: 'square',
          strokeStyle: 'solid',
        ),
      );

      expect(primitives, hasLength(1));
      final polygon = primitives.single as ArrowheadPolygonPrimitive;
      expect(polygon.fillMode, 'stroke');
      expect(polygon.points, hasLength(4));
      final maxX = polygon.points
          .map((point) => point[0])
          .reduce((left, right) => left > right ? left : right);
      expect(maxX, lessThanOrEqualTo(100 + 1e-6));
    });

    test('renders inverted triangle opposite to shaft heading', () {
      final primitives = getArrowheadRenderPrimitives(
        const ArrowheadRenderPrimitivesInput(
          arrowPoints: arrowPoints,
          strokeWidth: 2,
          curveOps: curveOps,
          position: arrowEndpointPositionEnd,
          arrowhead: 'inverted_triangle',
          strokeStyle: 'solid',
        ),
      );

      expect(primitives, hasLength(1));
      final polygon = primitives.single as ArrowheadPolygonPrimitive;
      expect(polygon.fillMode, 'stroke');
      expect(polygon.points, hasLength(3));
      expect(polygon.points.any((point) => point[0] > 100), isTrue);
    });

    test('direct render helpers accept square and inverted triangle', () {
      final squareSize = getArrowheadSize('square');
      final invertedTriangleSize = getArrowheadSize('inverted_triangle');

      expect(squareSize, isA<num>());
      expect(invertedTriangleSize, isA<num>());
    });
  });
}
