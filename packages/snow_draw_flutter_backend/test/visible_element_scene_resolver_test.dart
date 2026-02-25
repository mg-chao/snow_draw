import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

void main() {
  const viewport = DrawRect(maxX: 120, maxY: 120);

  test('keeps z-order when preview moves an offscreen element into view', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'back',
          rect: DrawRect(minX: 200, minY: 20, maxX: 240, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'middle',
          rect: DrawRect(minX: 10, minY: 20, maxX: 50, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'front',
          rect: DrawRect(minX: 60, minY: 20, maxX: 100, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ],
    );
    final preview = document
        .getElementById('back')!
        .copyWith(rect: const DrawRect(minX: 20, minY: 20, maxX: 40, maxY: 40));

    final resolved = resolveVisibleElementScene(
      document: document,
      viewportRect: viewport,
      previewElementsById: {'back': preview},
    );

    expect(resolved.map((e) => e.id).toList(), ['back', 'middle', 'front']);
  });

  test('drops an element when its preview moves outside the viewport', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'a',
          rect: DrawRect(minX: 10, minY: 10, maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'b',
          rect: DrawRect(minX: 50, minY: 10, maxX: 80, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ],
    );
    final preview = document
        .getElementById('a')!
        .copyWith(
          rect: const DrawRect(minX: 180, minY: 10, maxX: 220, maxY: 40),
        );

    final resolved = resolveVisibleElementScene(
      document: document,
      viewportRect: viewport,
      previewElementsById: {'a': preview},
    );

    expect(resolved.map((e) => e.id).toList(), ['b']);
  });
}
