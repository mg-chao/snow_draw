import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('queryElementsInRectOrdered returns ascending z-order', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'e0',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e1',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e2',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ],
    );

    final result = document.queryElementsInRectOrdered(
      const DrawRect(minX: 1, minY: 1, maxX: 5, maxY: 5),
    );
    expect(result.map((element) => element.id), ['e0', 'e1', 'e2']);
  });

  test('queryElementsAtPointTopDown returns descending z-order', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'e0',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e1',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e2',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ],
    );

    final result = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 3, y: 3),
      1,
    );
    expect(result.map((element) => element.id), ['e2', 'e1', 'e0']);
  });

  test('queryElementsAtPointTopDown keeps earlier query results stable', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'left',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'right',
          rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ],
    );

    final leftHit = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 5, y: 5),
      0.5,
    );
    final rightHit = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 25, y: 5),
      0.5,
    );

    expect(leftHit.map((element) => element.id), ['left']);
    expect(rightHit.map((element) => element.id), ['right']);
    expect(identical(leftHit, rightHit), isFalse);
  });

  test('queryElementsAtPointTopDown does not share result buffers '
      'across documents', () {
    final leftDocument = DocumentState(
      elements: const [
        ElementState(
          id: 'left',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ],
    );
    final rightDocument = DocumentState(
      elements: const [
        ElementState(
          id: 'right',
          rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ],
    );

    final leftHit = leftDocument.queryElementsAtPointTopDown(
      const DrawPoint(x: 5, y: 5),
      0.5,
    );
    final rightHit = rightDocument.queryElementsAtPointTopDown(
      const DrawPoint(x: 25, y: 5),
      0.5,
    );

    expect(leftHit.map((element) => element.id), ['left']);
    expect(rightHit.map((element) => element.id), ['right']);
    expect(identical(leftHit, rightHit), isFalse);
  });

  test('queryElementsInRectOrdered respects min and max bounds', () {
    final document = DocumentState(
      elements: const [
        ElementState(
          id: 'e0',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e1',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e2',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ],
    );

    final result = document.queryElementsInRectOrdered(
      const DrawRect(minX: 1, minY: 1, maxX: 5, maxY: 5),
      minOrderIndex: 1,
      maxOrderIndex: 1,
    );
    expect(result.map((element) => element.id), ['e1']);
  });
}
