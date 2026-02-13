import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/services/element_index_service.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('ElementIndexService', () {
    ElementState _element(String id) => ElementState(
      id: id,
      rect: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

    test('byId builds map from element list', () {
      final elements = [
        _element('a'),
        _element('b'),
        _element('c'),
      ];
      final index = ElementIndexService(elements);

      expect(index.byId.length, 3);
      expect(index.byId['a']?.id, 'a');
      expect(index.byId['b']?.id, 'b');
      expect(index.byId['c']?.id, 'c');
    });

    test('operator [] returns element by id', () {
      final elements = [_element('x')];
      final index = ElementIndexService(elements);

      expect(index['x']?.id, 'x');
      expect(index['missing'], isNull);
    });

    test('containsId returns correct result', () {
      final elements = [_element('a')];
      final index = ElementIndexService(elements);

      expect(index.containsId('a'), isTrue);
      expect(index.containsId('z'), isFalse);
    });

    test('byId is cached on repeated access', () {
      final elements = [_element('a')];
      final index = ElementIndexService(elements);

      final first = index.byId;
      final second = index.byId;

      expect(identical(first, second), isTrue);
    });

    test('byId returns unmodifiable map', () {
      final elements = [_element('a')];
      final index = ElementIndexService(elements);

      expect(
        () => index.byId['new'] = _element('x'),
        throwsUnsupportedError,
      );
    });

    test('empty element list produces empty index', () {
      final index = ElementIndexService([]);

      expect(index.byId, isEmpty);
      expect(index['anything'], isNull);
      expect(index.containsId('anything'), isFalse);
    });

    test('last element wins when duplicate ids exist', () {
      final a1 = ElementState(
        id: 'dup',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 1, maxY: 1),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: const RectangleData(),
      );
      final a2 = ElementState(
        id: 'dup',
        rect: const DrawRect(
          minX: 0,
          minY: 0,
          maxX: 99,
          maxY: 99,
        ),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: const RectangleData(),
      );
      final index = ElementIndexService([a1, a2]);

      expect(index['dup']?.rect.maxX, 99);
    });
  });
}
