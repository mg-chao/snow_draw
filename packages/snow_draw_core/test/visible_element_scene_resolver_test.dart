import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/visible_element_scene_resolver.dart';

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

  test('respects order-range filters while keeping preview-only elements', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'e0',
          rect: DrawRect(minX: 10, minY: 10, maxX: 30, maxY: 30),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e1',
          rect: DrawRect(minX: 40, minY: 10, maxX: 60, maxY: 30),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ],
    );
    final filteredPreview = document
        .getElementById('e0')!
        .copyWith(rect: const DrawRect(minX: 20, minY: 20, maxX: 40, maxY: 40));
    const previewOnly = ElementState(
      id: 'draft',
      rect: DrawRect(minX: 70, minY: 10, maxX: 90, maxY: 30),
      rotation: 0,
      opacity: 1,
      zIndex: 99,
      data: RectangleData(),
    );

    final resolved = resolveVisibleElementScene(
      document: document,
      viewportRect: viewport,
      minOrderIndex: 1,
      previewElementsById: {'e0': filteredPreview, 'draft': previewOnly},
    );

    expect(resolved.map((e) => e.id).toList(), ['e1', 'draft']);
  });
}
