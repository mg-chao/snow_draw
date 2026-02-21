import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_hit_tester.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  const tester = HighlightHitTester();
  const rect = DrawRect(maxX: 100, maxY: 100);
  const baseElement = ElementState(
    id: 'h1',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: HighlightData(),
  );

  test('rectangle highlight hits inside', () {
    final hit = tester.hitTest(
      element: baseElement,
      position: const DrawPoint(x: 50, y: 50),
    );
    expect(hit, isTrue);
  });

  test('ellipse highlight misses outside', () {
    final ellipseElement = baseElement.copyWith(
      data: const HighlightData(shape: HighlightShape.ellipse),
    );
    final hit = tester.hitTest(
      element: ellipseElement,
      position: const DrawPoint(x: 100, y: 0),
    );
    expect(hit, isFalse);
  });

  test('rectangle highlight with transparent fill still hits inside', () {
    final transparentElement = baseElement.copyWith(
      data: const HighlightData(color: DrawColor(0x00000000)),
    );

    final hit = tester.hitTest(
      element: transparentElement,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isTrue);
  });

  test('ellipse highlight with transparent fill still hits inside', () {
    final transparentEllipseElement = baseElement.copyWith(
      data: const HighlightData(
        shape: HighlightShape.ellipse,
        color: DrawColor(0x00000000),
      ),
    );

    final hit = tester.hitTest(
      element: transparentEllipseElement,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isTrue);
  });
}
