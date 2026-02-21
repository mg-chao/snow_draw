import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/visible_element_scene_cache.dart';

void main() {
  test('reuses last query for identical document and viewport', () {
    final cache = VisibleElementSceneCache();
    final document = DocumentState(elements: [_element('a', 0, 0)]);
    const viewport = DrawRect(maxX: 100, maxY: 100);

    final first = cache.resolve(document: document, viewportRect: viewport);
    final second = cache.resolve(document: document, viewportRect: viewport);

    expect(identical(first, second), isTrue);
  });

  test('invalidates cache when viewport changes', () {
    final cache = VisibleElementSceneCache();
    final document = DocumentState(elements: [_element('a', 0, 0)]);

    final first = cache.resolve(
      document: document,
      viewportRect: const DrawRect(maxX: 100, maxY: 100),
    );
    final second = cache.resolve(
      document: document,
      viewportRect: const DrawRect(minX: 20, minY: 20, maxX: 30, maxY: 30),
    );

    expect(identical(first, second), isFalse);
    expect(second, isEmpty);
  });

  test('invalidates cache when document identity changes', () {
    final cache = VisibleElementSceneCache();
    final firstDocument = DocumentState(elements: [_element('a', 0, 0)]);
    final secondDocument = firstDocument.copyWith(
      elements: [_element('a', 20, 20)],
    );
    const viewport = DrawRect(maxX: 100, maxY: 100);

    final first = cache.resolve(
      document: firstDocument,
      viewportRect: viewport,
    );
    final second = cache.resolve(
      document: secondDocument,
      viewportRect: viewport,
    );

    expect(identical(first, second), isFalse);
    expect(second.single.rect.minX, 20);
  });
}

ElementState _element(String id, double minX, double minY) => ElementState(
  id: id,
  rect: DrawRect(minX: minX, minY: minY, maxX: minX + 10, maxY: minY + 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);
