import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('queryElementsInRectOrdered returns ascending z-order', () {
    final document = _stackedRectangleDocument(['e0', 'e1', 'e2']);

    final result = document.queryElementsInRectOrdered(
      const DrawRect(minX: 1, minY: 1, maxX: 5, maxY: 5),
    );
    expect(_elementIds(result), ['e0', 'e1', 'e2']);
  });

  test('queryElementsAtPointTopDown returns descending z-order', () {
    final document = _stackedRectangleDocument(['e0', 'e1', 'e2']);

    final result = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 3, y: 3),
      1,
    );
    expect(_elementIds(result), ['e2', 'e1', 'e0']);
  });

  test('queryElementsAtPointTopDown keeps earlier query results stable', () {
    final document = _document([
      _rectangleElement(
        id: 'left',
        rect: const DrawRect(maxX: 10, maxY: 10),
        zIndex: 0,
      ),
      _rectangleElement(
        id: 'right',
        rect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
        zIndex: 1,
      ),
    ]);

    final leftHit = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 5, y: 5),
      0.5,
    );
    final rightHit = document.queryElementsAtPointTopDown(
      const DrawPoint(x: 25, y: 5),
      0.5,
    );

    expect(_elementIds(leftHit), ['left']);
    expect(_elementIds(rightHit), ['right']);
    expect(identical(leftHit, rightHit), isFalse);
  });

  test('queryElementsAtPointTopDown does not share result buffers '
      'across documents', () {
    final leftDocument = _document([
      _rectangleElement(
        id: 'left',
        rect: const DrawRect(maxX: 10, maxY: 10),
        zIndex: 0,
      ),
    ]);
    final rightDocument = _document([
      _rectangleElement(
        id: 'right',
        rect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
        zIndex: 0,
      ),
    ]);

    final leftHit = leftDocument.queryElementsAtPointTopDown(
      const DrawPoint(x: 5, y: 5),
      0.5,
    );
    final rightHit = rightDocument.queryElementsAtPointTopDown(
      const DrawPoint(x: 25, y: 5),
      0.5,
    );

    expect(_elementIds(leftHit), ['left']);
    expect(_elementIds(rightHit), ['right']);
    expect(identical(leftHit, rightHit), isFalse);
  });

  test('queryElementsInRectOrdered respects min and max bounds', () {
    final document = _stackedRectangleDocument(['e0', 'e1', 'e2']);

    final result = document.queryElementsInRectOrdered(
      const DrawRect(minX: 1, minY: 1, maxX: 5, maxY: 5),
      minOrderIndex: 1,
      maxOrderIndex: 1,
    );
    expect(_elementIds(result), ['e1']);
  });

  test('boundTextIds exposes an immutable view', () {
    final document = _document([
      _serialNumberElement(id: 'serial', textElementId: 'text'),
    ]);

    expect(document.boundTextIds, contains('text'));
    expect(() => document.boundTextIds.add('new-text'), throwsUnsupportedError);
  });
}

DocumentState _stackedRectangleDocument(List<String> ids) => _document([
  for (var index = 0; index < ids.length; index += 1)
    _rectangleElement(id: ids[index], zIndex: index),
]);

DocumentState _document(List<ElementState> elements) =>
    DocumentState(elements: elements);

ElementState _rectangleElement({
  required String id,
  required int zIndex,
  DrawRect rect = const DrawRect(maxX: 20, maxY: 20),
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _serialNumberElement({
  required String id,
  required String textElementId,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 20, maxY: 20),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: SerialNumberData(textElementId: textElementId),
);

List<String> _elementIds(Iterable<ElementState> elements) =>
    elements.map((element) => element.id).toList(growable: false);
