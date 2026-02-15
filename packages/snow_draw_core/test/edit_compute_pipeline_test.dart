import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/core/edit_compute_pipeline.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  DrawState stateWith(List<ElementState> elements) => DrawState(
    domain: DomainState(document: DocumentState(elements: elements)),
  );

  ElementState rect0({
    required String id,
    DrawRect rect = const DrawRect(maxX: 100, maxY: 100),
  }) => ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: const RectangleData(),
  );

  ElementState arrow0({
    required String id,
    required List<DrawPoint> points,
    ArrowBinding? startBinding,
    ArrowBinding? endBinding,
  }) {
    final rect = _rectForPoints(points);
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: points,
      rect: rect,
    );
    return ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: ArrowData(
        points: normalized,
        startBinding: startBinding,
        endBinding: endBinding,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Tests
  // -----------------------------------------------------------------------

  group('EditComputePipeline.finalize', () {
    test('returns null for empty updatedById', () {
      final state = stateWith([rect0(id: 'r1')]);
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {},
      );
      expect(result, isNull);
    });

    test('returns result with updated elements for non-empty map', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
      );
      expect(result, isNotNull);
      expect(result!.updatedElements['r1']!.rect.minX, 10);
    });

    test(
      'keeps caller map untouched when no post-processing updates are needed',
      () {
        final r1 = rect0(id: 'r1');
        final state = stateWith([r1]);
        final moved = r1.copyWith(
          rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
        );
        final callerMap = <String, ElementState>{'r1': moved};

        final result = EditComputePipeline.finalize(
          state: state,
          updatedById: callerMap,
        );

        expect(result, isNotNull);
        expect(identical(callerMap['r1'], moved), isTrue);
        expect(identical(result!.updatedElements['r1'], moved), isTrue);
      },
    );

    test('does not mutate the caller map keys', () {
      final target = rect0(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = arrow0(
        id: 'boundArrow',
        points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
        startBinding: binding,
      );
      final state = stateWith([target, arrow]);

      // Move the target - the resolver would add 'boundArrow' to the
      // result. The caller's map must not gain that extra key.
      final movedTarget = target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final callerMap = <String, ElementState>{'target': movedTarget};
      final keysBefore = callerMap.keys.toSet();

      EditComputePipeline.finalize(state: state, updatedById: callerMap);

      // The caller's map must not have been mutated by finalize.
      expect(callerMap.keys.toSet(), equals(keysBefore));
    });

    test('does not mutate the caller map values', () {
      final target = rect0(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = arrow0(
        id: 'arrow',
        points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
        startBinding: binding,
      );
      final state = stateWith([target, arrow]);

      // Move the arrow - unbinding should not overwrite the caller's
      // value.
      final movedArrow = arrow.copyWith(
        rect: const DrawRect(minX: 60, minY: 79, maxX: 250, maxY: 81),
      );
      final callerMap = <String, ElementState>{'arrow': movedArrow};

      EditComputePipeline.finalize(state: state, updatedById: callerMap);

      // The caller's map value must still be the original movedArrow.
      expect(identical(callerMap['arrow'], movedArrow), isTrue);
    });

    test('unbinds arrow-like elements in the result', () {
      final target = rect0(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = arrow0(
        id: 'arrow',
        points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
        startBinding: binding,
      );
      final state = stateWith([target, arrow]);

      final movedArrow = arrow.copyWith(
        rect: const DrawRect(minX: 60, minY: 79, maxX: 250, maxY: 81),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'arrow': movedArrow},
      );

      expect(result, isNotNull);
      final resultArrow = result!.updatedElements['arrow']!;
      final data = resultArrow.data as ArrowData;
      expect(data.startBinding, isNull);
    });

    test('passes through multiSelectBounds and multiSelectRotation', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      const bounds = DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110);
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
        multiSelectBounds: bounds,
        multiSelectRotation: 1.5,
      );
      expect(result!.multiSelectBounds, equals(bounds));
      expect(result.multiSelectRotation, 1.5);
    });

    test('skipBindingUpdate predicate excludes elements', () {
      final target = rect0(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = arrow0(
        id: 'boundArrow',
        points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
        startBinding: binding,
      );
      final state = stateWith([target, arrow]);

      // Move the target - the resolver would normally update the
      // bound arrow. The skip predicate should prevent that.
      final movedTarget = target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'target': movedTarget},
        skipBindingUpdate: (id, _) => id == 'boundArrow',
      );

      expect(result, isNotNull);
      // The bound arrow should NOT appear in the result because
      // the skip predicate excluded it.
      expect(result!.updatedElements.containsKey('boundArrow'), isFalse);
    });

    test('resolves bindings when bound target moves', () {
      final target = rect0(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = arrow0(
        id: 'boundArrow',
        points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
        startBinding: binding,
      );
      final state = stateWith([target, arrow]);

      // Move the target - the resolver should update the bound arrow.
      final movedTarget = target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'target': movedTarget},
      );

      expect(result, isNotNull);
      // The bound arrow should appear in the result because the
      // resolver updated it.
      expect(result!.updatedElements.containsKey('boundArrow'), isTrue);
    });

    test('result updatedElements is unmodifiable', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
      );
      expect(result, isNotNull);
      expect(
        () => result!.updatedElements['new'] = moved,
        throwsUnsupportedError,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }

  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
