import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_hit_tester.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  const rect = DrawRect(maxX: 100, maxY: 100);
  const element = ElementState(
    id: 'h1',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: HighlightData(),
  );

  test('rectangle highlight hits inside', () {
    const tester = HighlightHitTester();
    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );
    expect(hit, isTrue);
  });

  test('ellipse highlight misses outside', () {
    const tester = HighlightHitTester();
    const ellipseElement = ElementState(
      id: 'h2',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(shape: HighlightShape.ellipse),
    );
    final hit = tester.hitTest(
      element: ellipseElement,
      position: const DrawPoint(x: 100, y: 0),
    );
    expect(hit, isFalse);
  });
}
