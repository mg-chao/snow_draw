import 'dart:math' as math;

import 'package:snow_draw_engine/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_engine/draw/elements/types/filter/filter_hit_tester.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  const tester = FilterHitTester();
  const rect = DrawRect(maxX: 100, maxY: 50);
  const baseFilterElement = ElementState(
    id: 'filter',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: FilterData(),
  );

  test('hits inside an unrotated filter rect', () {
    final hit = tester.hitTest(
      element: baseFilterElement,
      position: const DrawPoint(x: 40, y: 20),
    );

    expect(hit, isTrue);
  });

  test('uses local-space conversion for rotated filters', () {
    final hit = tester.hitTest(
      element: baseFilterElement.copyWith(rotation: math.pi / 2),
      position: const DrawPoint(x: 50, y: 70),
    );

    expect(hit, isTrue);
  });

  test('throws when element data is not filter data', () {
    final invalidElement = baseFilterElement.copyWith(
      id: 'not-filter',
      data: const TextData(),
    );

    expect(
      () => tester.hitTest(
        element: invalidElement,
        position: const DrawPoint(x: 10, y: 10),
      ),
      throwsStateError,
    );
  });
}
