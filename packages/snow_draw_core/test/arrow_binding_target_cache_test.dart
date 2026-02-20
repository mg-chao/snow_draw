import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

const _defaultArrowType = ArrowType.curved;
const _defaultArrowheadStyle = ArrowheadStyle.none;
const _defaultShouldLookupBindings = true;
const _defaultAllowNewBinding = true;
const _defaultHasBindableTargets = true;

typedef _ResolvedCandidate = ({bool hasValue, ArrowBindingResult? value});

void main() {
  group('ArrowBindingTargetCache candidate caching', () {
    test('returns no candidate before caching', () {
      final cache = ArrowBindingTargetCache();
      final resolved = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 10, y: 12),
        referencePoint: null,
        positionThreshold: 4,
        referenceThreshold: 4,
        elementsVersion: 3,
        snapDistance: 10,
        preferredBinding: null,
      );

      expect(resolved.hasValue, isFalse);
      expect(resolved.value, isNull);
    });

    test('reuses cached miss when null value is stored', () {
      final cache = ArrowBindingTargetCache();
      _cacheCandidate(
        cache,
        position: const DrawPoint(x: 100, y: 120),
        referencePoint: const DrawPoint(x: 80, y: 90),
        elementsVersion: 7,
        snapDistance: 12,
        preferredBinding: null,
        value: null,
      );

      final resolved = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 102, y: 121),
        referencePoint: const DrawPoint(x: 79, y: 92),
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 7,
        snapDistance: 12,
        preferredBinding: null,
      );
      final resolvedFar = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 110, y: 126),
        referencePoint: const DrawPoint(x: 79, y: 92),
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 7,
        snapDistance: 12,
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
      _cacheCandidate(
        cache,
        position: const DrawPoint(x: 40, y: 40),
        referencePoint: null,
        elementsVersion: 2,
        snapDistance: 8,
        preferredBinding: initialBinding,
        value: const ArrowBindingResult(
          binding: initialBinding,
          snapPoint: DrawPoint(x: 40, y: 40),
          distance: 0,
          zIndex: 3,
        ),
      );

      final resolved = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 40, y: 40),
        referencePoint: null,
        positionThreshold: 4,
        referenceThreshold: 4,
        elementsVersion: 2,
        snapDistance: 8,
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
      _cacheCandidate(
        cache,
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
        value: expected,
      );

      final resolvedFar = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 30, y: 30),
        referencePoint: null,
        positionThreshold: 5,
        referenceThreshold: 5,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
      );
      final resolvedNear = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 12, y: 12),
        referencePoint: null,
        positionThreshold: 5,
        referenceThreshold: 5,
        elementsVersion: 5,
        snapDistance: 10,
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

      _cacheCandidate(
        cache,
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
        value: hit,
      );
      final hitResolution = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 15, y: 10),
        referencePoint: null,
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
      );

      _cacheCandidate(
        cache,
        position: const DrawPoint(x: 10, y: 10),
        referencePoint: null,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
        value: null,
      );
      final missResolution = _resolveCandidate(
        cache,
        position: const DrawPoint(x: 15, y: 10),
        referencePoint: null,
        positionThreshold: 6,
        referenceThreshold: 6,
        elementsVersion: 5,
        snapDistance: 10,
        preferredBinding: binding,
      );

      expect(hitResolution.hasValue, isTrue);
      expect(hitResolution.value, same(hit));
      expect(missResolution.hasValue, isFalse);
      expect(missResolution.value, isNull);
    });
  });
}

void _cacheCandidate(
  ArrowBindingTargetCache cache, {
  required DrawPoint position,
  required DrawPoint? referencePoint,
  required int elementsVersion,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
  required ArrowBindingResult? value,
}) {
  cache.cacheCandidate(
    position: position,
    referencePoint: referencePoint,
    elementsVersion: elementsVersion,
    snapDistance: snapDistance,
    arrowType: _defaultArrowType,
    arrowheadStyle: _defaultArrowheadStyle,
    shouldLookupBindings: _defaultShouldLookupBindings,
    allowNewBinding: _defaultAllowNewBinding,
    hasBindableTargets: _defaultHasBindableTargets,
    preferredBinding: preferredBinding,
    value: value,
  );
}

_ResolvedCandidate _resolveCandidate(
  ArrowBindingTargetCache cache, {
  required DrawPoint position,
  required DrawPoint? referencePoint,
  required double positionThreshold,
  required double referenceThreshold,
  required int elementsVersion,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
}) => cache.resolveCandidate(
  position: position,
  referencePoint: referencePoint,
  positionThreshold: positionThreshold,
  referenceThreshold: referenceThreshold,
  elementsVersion: elementsVersion,
  snapDistance: snapDistance,
  arrowType: _defaultArrowType,
  arrowheadStyle: _defaultArrowheadStyle,
  shouldLookupBindings: _defaultShouldLookupBindings,
  allowNewBinding: _defaultAllowNewBinding,
  hasBindableTargets: _defaultHasBindableTargets,
  preferredBinding: preferredBinding,
);
