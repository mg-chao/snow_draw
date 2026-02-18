import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('ArrowBindingTargetCache candidate caching', () {
    test('returns no candidate before caching', () {
      final cache = ArrowBindingTargetCache();
      final resolved = cache.resolveCandidate(
        position: const DrawPoint(x: 10, y: 12),
        referencePoint: null,
        positionThreshold: 4,
        referenceThreshold: 4,
        elementsVersion: 3,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: null,
      );

      expect(resolved.hasValue, isFalse);
      expect(resolved.value, isNull);
    });

    test('reuses cached miss when null value is stored', () {
      final cache = ArrowBindingTargetCache()
        ..cacheCandidate(
          position: const DrawPoint(x: 100, y: 120),
          referencePoint: const DrawPoint(x: 80, y: 90),
          elementsVersion: 7,
          snapDistance: 12,
          arrowType: ArrowType.curved,
          arrowheadStyle: ArrowheadStyle.none,
          shouldLookupBindings: true,
          allowNewBinding: true,
          hasBindableTargets: true,
          preferredBinding: null,
          value: null,
        );

      final resolved = cache.resolveCandidate(
        position: const DrawPoint(x: 102, y: 121),
        referencePoint: const DrawPoint(x: 79, y: 92),
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 7,
        snapDistance: 12,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: null,
      );
      final resolvedFar = cache.resolveCandidate(
        position: const DrawPoint(x: 110, y: 126),
        referencePoint: const DrawPoint(x: 79, y: 92),
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 7,
        snapDistance: 12,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: null,
      );

      expect(resolved.hasValue, isTrue);
      expect(resolved.value, isNull);
      expect(resolvedFar.hasValue, isFalse);
      expect(resolvedFar.value, isNull);
    });

    test('invalidates when preferred binding changes', () {
      final cache = ArrowBindingTargetCache();
      const initialBinding = ArrowBinding(
        elementId: 'target-a',
        anchor: DrawPoint(x: 0.5, y: 0.5),
      );
      cache.cacheCandidate(
        position: const DrawPoint(x: 40, y: 40),
        referencePoint: null,
        elementsVersion: 2,
        snapDistance: 8,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: initialBinding,
        value: const ArrowBindingResult(
          binding: initialBinding,
          snapPoint: DrawPoint(x: 40, y: 40),
          distance: 0,
          zIndex: 3,
        ),
      );

      final resolved = cache.resolveCandidate(
        position: const DrawPoint(x: 40, y: 40),
        referencePoint: null,
        positionThreshold: 4,
        referenceThreshold: 4,
        elementsVersion: 2,
        snapDistance: 8,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: const ArrowBinding(
          elementId: 'target-b',
          anchor: DrawPoint(x: 0.5, y: 0.5),
        ),
      );

      expect(resolved.hasValue, isFalse);
      expect(resolved.value, isNull);
    });

    test('invalidates when pointer moves beyond cache threshold', () {
      final cache = ArrowBindingTargetCache();
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.2, y: 0.2),
      );
      const expected = ArrowBindingResult(
        binding: binding,
        snapPoint: DrawPoint(x: 10, y: 10),
        distance: 1,
        zIndex: 1,
      );
      cache.cacheCandidate(
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
        value: expected,
      );

      final resolvedFar = cache.resolveCandidate(
        position: const DrawPoint(x: 30, y: 30),
        referencePoint: null,
        positionThreshold: 5,
        referenceThreshold: 5,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
      );
      final resolvedNear = cache.resolveCandidate(
        position: const DrawPoint(x: 12, y: 12),
        referencePoint: null,
        positionThreshold: 5,
        referenceThreshold: 5,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
      );

      expect(resolvedFar.hasValue, isFalse);
      expect(resolvedNear.hasValue, isTrue);
      expect(resolvedNear.value, same(expected));
    });

    test('cached miss uses a tighter reuse threshold than cached hits', () {
      final cache = ArrowBindingTargetCache();
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.2, y: 0.2),
      );
      const hit = ArrowBindingResult(
        binding: binding,
        snapPoint: DrawPoint(x: 10, y: 10),
        distance: 1,
        zIndex: 1,
      );

      cache.cacheCandidate(
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
        value: hit,
      );
      final hitResolution = cache.resolveCandidate(
        position: const DrawPoint(x: 15, y: 10),
        referencePoint: null,
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
      );

      cache.cacheCandidate(
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
        value: null,
      );
      final missResolution = cache.resolveCandidate(
        position: const DrawPoint(x: 15, y: 10),
        referencePoint: null,
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 5,
        snapDistance: 10,
        arrowType: ArrowType.curved,
        arrowheadStyle: ArrowheadStyle.none,
        shouldLookupBindings: true,
        allowNewBinding: true,
        hasBindableTargets: true,
        preferredBinding: binding,
      );

      expect(hitResolution.hasValue, isTrue);
      expect(hitResolution.value, same(hit));
      expect(missResolution.hasValue, isFalse);
      expect(missResolution.value, isNull);
    });
  });
}
