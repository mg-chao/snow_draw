import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/apply/edit_apply.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

ElementState _element(String id, {DrawRect? rect}) => ElementState(
  id: id,
  rect: rect ?? const DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

void main() {
  group('EditApply.replaceElementsById', () {
    late List<ElementState> elements;

    setUp(() {
      elements = List.generate(5, (i) => _element('e$i'));
    });

    test('returns same list when replacements map is empty', () {
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {},
      );
      expect(identical(result, elements), isTrue);
    });

    test('returns same list when replacement is identical', () {
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e2': elements[2]},
      );
      expect(identical(result, elements), isTrue);
    });

    test('replaces a single element', () {
      final replacement = elements[2].copyWith(
        rect: const DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200),
      );
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e2': replacement},
      );
      expect(result.length, elements.length);
      expect(identical(result[0], elements[0]), isTrue);
      expect(identical(result[2], replacement), isTrue);
      expect(identical(result[4], elements[4]), isTrue);
    });

    test('replaces multiple elements', () {
      final r0 = elements[0].copyWith(
        rect: const DrawRect(minX: 50, minY: 50, maxX: 60, maxY: 60),
      );
      final r4 = elements[4].copyWith(
        rect: const DrawRect(minX: 90, minY: 90, maxX: 100, maxY: 100),
      );
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e0': r0, 'e4': r4},
      );
      expect(result.length, elements.length);
      expect(identical(result[0], r0), isTrue);
      expect(identical(result[4], r4), isTrue);
      expect(identical(result[1], elements[1]), isTrue);
    });

    test('ignores replacement for non-existent id', () {
      final replacement = _element('ghost');
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'ghost': replacement},
      );
      expect(identical(result, elements), isTrue);
    });

    test('preserves element order', () {
      final replacement = elements[3].copyWith(
        rect: const DrawRect(minX: 70, minY: 70, maxX: 80, maxY: 80),
      );
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e3': replacement},
      );
      final ids = result.map((e) => e.id).toList();
      expect(ids, ['e0', 'e1', 'e2', 'e3', 'e4']);
    });

    test('works with large lists (indexed path)', () {
      final large = List.generate(200, (i) => _element('el$i'));
      final replacement = large[150].copyWith(
        rect: const DrawRect(minX: 999, minY: 999, maxX: 1000, maxY: 1000),
      );
      final result = EditApply.replaceElementsById(
        elements: large,
        replacementsById: {'el150': replacement},
      );
      expect(result.length, 200);
      expect(identical(result[150], replacement), isTrue);
      expect(result[150].rect.minX, 999);
      expect(identical(result[0], large[0]), isTrue);
      expect(identical(result[199], large[199]), isTrue);
    });

    test('large list returns same list when no actual changes', () {
      final large = List.generate(200, (i) => _element('el$i'));
      final result = EditApply.replaceElementsById(
        elements: large,
        replacementsById: {'el50': large[50]},
      );
      expect(identical(result, large), isTrue);
    });

    test('treats value-equal replacement as no-op', () {
      final equalButNewInstance = elements[2].copyWith();
      expect(identical(equalButNewInstance, elements[2]), isFalse);
      expect(equalButNewInstance, equals(elements[2]));

      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e2': equalButNewInstance},
      );

      expect(identical(result, elements), isTrue);
      expect(identical(result[2], elements[2]), isTrue);
    });

    test('large list with full replacement map keeps equal elements '
        'and applies only real changes', () {
      final large = List.generate(200, (i) => _element('el$i'));
      final replacements = <String, ElementState>{};
      for (var i = 0; i < large.length; i++) {
        replacements['el$i'] = large[i].copyWith();
      }
      final changed = large[123].copyWith(
        rect: const DrawRect(minX: 999, minY: 999, maxX: 1000, maxY: 1000),
      );
      replacements['el123'] = changed;

      final result = EditApply.replaceElementsById(
        elements: large,
        replacementsById: replacements,
      );

      expect(identical(result, large), isFalse);
      expect(result.length, large.length);
      expect(identical(result[123], changed), isTrue);
      expect(identical(result[50], large[50]), isTrue);
      expect(result[123].rect.minX, 999);
    });
  });
}
