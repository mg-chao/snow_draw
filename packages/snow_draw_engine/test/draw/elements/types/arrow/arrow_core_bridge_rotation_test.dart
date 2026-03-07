import 'dart:math' as math;

import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_bridge rotation integration', () {
    test('toCoreArrowState projects rotated world points correctly', () {
      final element = _buildRotatedArrowElement();
      final data = element.data as ArrowData;
      final unrotated = ConnectorGeometry.resolveWorldPoints(
        rect: element.rect,
        normalizedPoints: data.points,
      );
      final space = ElementSpace(
        rotation: element.rotation,
        origin: element.rect.center,
      );
      final expectedWorldPoints = unrotated
          .map(space.toWorld)
          .toList(growable: false);

      final coreArrow = toCoreArrowState(element: element, data: data);
      final actualWorldPoints = coreArrowWorldPoints(coreArrow);

      expect(actualWorldPoints.length, expectedWorldPoints.length);
      for (var index = 0; index < actualWorldPoints.length; index++) {
        expect(
          actualWorldPoints[index].x,
          closeTo(expectedWorldPoints[index].x, 1e-6),
        );
        expect(
          actualWorldPoints[index].y,
          closeTo(expectedWorldPoints[index].y, 1e-6),
        );
      }
    });

    test('applyCoreArrowStateToElement preserves rotated rendered points', () {
      final element = _buildRotatedArrowElement();
      final data = element.data as ArrowData;
      final coreArrow = toCoreArrowState(element: element, data: data);

      final patched = applyCoreArrowStateToElement(
        element: element,
        data: data,
        nextArrow: coreArrow,
      );

      final patchedWorldPoints = _resolveRenderedWorldPoints(patched);
      final originalWorldPoints = _resolveRenderedWorldPoints(element);
      expect(patchedWorldPoints.length, originalWorldPoints.length);

      for (var index = 0; index < patchedWorldPoints.length; index++) {
        expect(
          patchedWorldPoints[index].x,
          closeTo(originalWorldPoints[index].x, 1e-6),
        );
        expect(
          patchedWorldPoints[index].y,
          closeTo(originalWorldPoints[index].y, 1e-6),
        );
      }
    });
  });
}

ElementState _buildRotatedArrowElement() => const ElementState(
  id: 'rotated-arrow',
  rect: DrawRect(minX: 20, minY: 10, maxX: 140, maxY: 70),
  rotation: math.pi / 6,
  opacity: 1,
  zIndex: 0,
  data: ArrowData(
    points: <DrawPoint>[
      DrawPoint(x: 0, y: 0.2),
      DrawPoint(x: 0.4, y: 0.8),
      DrawPoint(x: 1, y: 0.6),
    ],
    arrowType: ArrowType.curved,
  ),
);

List<DrawPoint> _resolveRenderedWorldPoints(ElementState element) {
  final data = element.data as ConnectorData;
  final unrotatedPoints = ConnectorGeometry.resolveWorldPoints(
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
