import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_hit_tester.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  const tester = FilterHitTester();
  const rect = DrawRect(maxX: 100, maxY: 50);

  test('hits inside an unrotated filter rect', () {
    const element = ElementState(
      id: 'filter',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FilterData(),
    );

    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 40, y: 20),
    );

    expect(hit, isTrue);
  });

  test('uses local-space conversion for rotated filters', () {
    const element = ElementState(
      id: 'filter',
      rect: rect,
      rotation: math.pi / 2,
      opacity: 1,
      zIndex: 0,
      data: FilterData(),
    );

    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 70),
    );

    expect(hit, isTrue);
  });

  test('throws when element data is not filter data', () {
    const element = ElementState(
      id: 'not-filter',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(),
    );

    expect(
      () => tester.hitTest(
        element: element,
        position: const DrawPoint(x: 10, y: 10),
      ),
      throwsStateError,
    );
  });
}
