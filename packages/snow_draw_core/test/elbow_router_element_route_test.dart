import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/core/coordinates/element_space.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

void main() {
  test('routeElbowArrowForElement keeps local/world points in sync', () {
    const worldPoints = <DrawPoint>[
      DrawPoint(x: 20, y: 40),
      DrawPoint(x: 220, y: 140),
    ];
    final rect = elbowRectForPoints(worldPoints);
    final data = ArrowData(
      points: ArrowGeometry.normalizePoints(
        worldPoints: worldPoints,
        rect: rect,
      ),
      arrowType: ArrowType.elbow,
    );
    final element = ElementState(
      id: 'arrow',
      rect: rect,
      rotation: math.pi / 6,
      opacity: 1,
      zIndex: 0,
      data: data,
    );

    final result = routeElbowArrowForElement(
      element: element,
      data: data,
      elementsById: const {},
    );

    expect(result.localPoints.length, result.worldPoints.length);
    expect(result.localPoints.length, greaterThanOrEqualTo(2));

    final elementSpace = ElementSpace(
      rotation: element.rotation,
      origin: element.rect.center,
    );
    for (var i = 0; i < result.localPoints.length; i++) {
      expect(
        elbowPointsClose(
          elementSpace.toWorld(result.localPoints[i]),
          result.worldPoints[i],
        ),
        isTrue,
      );
    }

    expect(elbowPathIsOrthogonal(result.worldPoints, epsilon: 1e-3), isTrue);
  });
}
