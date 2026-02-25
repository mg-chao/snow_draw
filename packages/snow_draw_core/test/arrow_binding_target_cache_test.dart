import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowBindingTargetCache target lookup caching', () {
    test('is invalid before any query is cached', () {
      final cache = ArrowBindingTargetCache();

      final valid = cache.isValid(
        position: const DrawPoint(x: 10, y: 10),
        threshold: 6,
        distance: 20,
        elementsVersion: 3,
      );

      expect(valid, isFalse);
      expect(cache.targets, isEmpty);
    });

    test('reuses cached targets when query stays within threshold', () {
      final cache = ArrowBindingTargetCache();
      final targets = [_element('target', const DrawRect(maxX: 10, maxY: 10))];
      cache.update(
        position: const DrawPoint(x: 100, y: 120),
        distance: 24,
        elementsVersion: 7,
        targets: targets,
      );

      final nearValid = cache.isValid(
        position: const DrawPoint(x: 102, y: 121),
        threshold: 4,
        distance: 24,
        elementsVersion: 7,
      );
      final farValid = cache.isValid(
        position: const DrawPoint(x: 108, y: 126),
        threshold: 4,
        distance: 24,
        elementsVersion: 7,
      );

      expect(nearValid, isTrue);
      expect(farValid, isFalse);
      expect(cache.targets, same(targets));
    });

    test('invalidates when elements version changes', () {
      final cache = ArrowBindingTargetCache()
        ..update(
          position: const DrawPoint(x: 20, y: 20),
          distance: 10,
          elementsVersion: 5,
          targets: [_element('target', const DrawRect(maxX: 10, maxY: 10))],
        );

      final valid = cache.isValid(
        position: const DrawPoint(x: 20, y: 20),
        threshold: 2,
        distance: 10,
        elementsVersion: 6,
      );

      expect(valid, isFalse);
    });

    test('invalidates when lookup distance changes', () {
      final cache = ArrowBindingTargetCache()
        ..update(
          position: const DrawPoint(x: 20, y: 20),
          distance: 12,
          elementsVersion: 5,
          targets: [_element('target', const DrawRect(maxX: 10, maxY: 10))],
        );

      final valid = cache.isValid(
        position: const DrawPoint(x: 20, y: 20),
        threshold: 2,
        distance: 14,
        elementsVersion: 5,
      );

      expect(valid, isFalse);
    });

    test('reset clears cached query and targets', () {
      final cache = ArrowBindingTargetCache()
        ..update(
          position: const DrawPoint(x: 30, y: 30),
          distance: 12,
          elementsVersion: 5,
          targets: [_element('target', const DrawRect(maxX: 10, maxY: 10))],
        )
        ..reset();

      final valid = cache.isValid(
        position: const DrawPoint(x: 30, y: 30),
        threshold: 2,
        distance: 12,
        elementsVersion: 5,
      );
      expect(valid, isFalse);
      expect(cache.targets, isEmpty);
    });
  });
}

ElementState _element(String id, DrawRect rect) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);
