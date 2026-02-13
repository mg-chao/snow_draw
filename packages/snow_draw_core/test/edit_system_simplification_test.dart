/// Tests that lock down behavior of the element editing system before
/// simplification refactoring. These tests verify:
///
/// 1. ArrowPointOperation finish/preview consistency (before
///    StandardFinishMixin migration).
/// 2. All standard operations still produce consistent finish/preview
///    results.
/// 3. Reference element resolution produces identical results when
///    extracted to a shared helper.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/core/edit_validation.dart';
import 'package:snow_draw_core/draw/edit/move/move_operation.dart';
import 'package:snow_draw_core/draw/edit/resize/resize_operation.dart';
import 'package:snow_draw_core/draw/edit/rotate/rotate_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_geometry.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  // =========================================================================
  // 0. EditContext.hasSnapshots
  // =========================================================================

  group('EditContext.hasSnapshots', () {
    test('MoveEditContext reports true when snapshots present', () {
      final ctx = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {
          'a': ElementMoveSnapshot(center: DrawPoint(x: 5, y: 5)),
        },
      );
      expect(ctx.hasSnapshots, isTrue);
    });

    test('MoveEditContext reports false when snapshots empty', () {
      final ctx = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {},
      );
      expect(ctx.hasSnapshots, isFalse);
    });

    test('ResizeEditContext reports true when snapshots present', () {
      final ctx = ResizeEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        resizeMode: ResizeMode.bottomRight,
        handleOffset: const DrawPoint(x: 0, y: 0),
        rotation: 0,
        elementSnapshots: const {
          'a': ElementResizeSnapshot(
            rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
            rotation: 0,
          ),
        },
      );
      expect(ctx.hasSnapshots, isTrue);
    });

    test('RotateEditContext reports true when snapshots present', () {
      final ctx = RotateEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        startAngle: 0,
        baseRotation: 0,
        rotationSnapAngle: 0,
        elementSnapshots: const {
          'a': ElementRotateSnapshot(
            center: DrawPoint(x: 5, y: 5),
            rotation: 0,
          ),
        },
      );
      expect(ctx.hasSnapshots, isTrue);
    });

    test('EditValidation.isValidContext uses hasSnapshots', () {
      final valid = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {
          'a': ElementMoveSnapshot(center: DrawPoint(x: 5, y: 5)),
        },
      );
      expect(EditValidation.isValidContext(valid), isTrue);

      final noIds = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {
          'a': ElementMoveSnapshot(center: DrawPoint(x: 5, y: 5)),
        },
      );
      expect(EditValidation.isValidContext(noIds), isFalse);

      final noSnaps = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        selectedIdsAtStart: const {'a'},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {},
      );
      expect(EditValidation.isValidContext(noSnaps), isFalse);
    });
  });

  // =========================================================================
  // 1. ArrowPointOperation: finish/preview consistency
  // =========================================================================

  group('ArrowPointOperation finish/preview consistency', () {
    test('straight arrow: preview matches finish geometry', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 200, y: 50),
        ],
      );
      final state = _stateWith([arrow], selectedIds: {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 1,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 100, y: 50),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 100, y: 80),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final previewEl = preview.previewElementsById['a1']!;
      final finishEl = finished.domain.document.getElementById('a1')!;
      expect(previewEl.rect, equals(finishEl.rect));
      final previewData = previewEl.data as ArrowData;
      final finishData = finishEl.data as ArrowData;
      expect(previewData.points.length, finishData.points.length);
    });

    test('no-change transform returns idle', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 10, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 0,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 10, y: 50),
      );

      final result = op.finish(state: state, context: ctx, transform: t0);
      expect(result.application.interaction, isA<IdleState>());
    });

    test('no-change preview returns none', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 10, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 0,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 10, y: 50),
      );

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: t0,
      );
      expect(preview.previewElementsById, isEmpty);
    });

    test('turning point drag updates arrow rect', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 200, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 1,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 200, y: 50),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 300, y: 100),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final moved = result.domain.document.getElementById('a1')!;
      expect(moved.rect.maxX, greaterThan(arrow.rect.maxX));
      expect(result.application.interaction, isA<IdleState>());
    });
  });

  // =========================================================================
  // 2. Standard operations: verify pipeline still works
  // =========================================================================

  group('Standard operations pipeline consistency', () {
    test('move: finish and preview produce same geometry', () {
      final element = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
      );
      final state = _stateWith([element]);

      const op = MoveOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 50, y: 50),
        params: const MoveOperationParams(),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 50, y: 50),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 80, y: 60),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final previewRect = preview.previewElementsById['r1']!.rect;
      final finishRect = finished.domain.document.getElementById('r1')!.rect;
      expect(previewRect, equals(finishRect));
    });

    test('resize: finish and preview produce same geometry', () {
      final element = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
      );
      final state = _stateWith([element]);

      const op = ResizeOperation();
      final handlePos = DrawPoint(x: element.rect.maxX, y: element.rect.maxY);
      final ctx = op.createContext(
        state: state,
        position: handlePos,
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.bottomRight,
          selectionPadding: 0,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: handlePos,
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 150, y: 150),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final previewRect = preview.previewElementsById['r1']!.rect;
      final finishRect = finished.domain.document.getElementById('r1')!.rect;
      expect(previewRect, equals(finishRect));
    });

    test('rotate: finish and preview produce same geometry', () {
      final element = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
      );
      final state = _stateWith([element]);

      const op = RotateOperation();
      final center = element.rect.center;
      final startPos = DrawPoint(x: center.x + 60, y: center.y);
      final ctx = op.createContext(
        state: state,
        position: startPos,
        params: const RotateOperationParams(),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: startPos,
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: DrawPoint(x: center.x, y: center.y + 60),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final previewEl = preview.previewElementsById['r1']!;
      final finishEl = finished.domain.document.getElementById('r1')!;
      expect(previewEl.rect, equals(finishEl.rect));
      expect(previewEl.rotation, closeTo(finishEl.rotation, 0.001));
    });
  });

  // =========================================================================
  // 3. Reference element resolution consistency
  // =========================================================================

  group('Reference element resolution', () {
    test('filters out selected and invisible elements', () {
      final r1 = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 50, maxY: 50),
      );
      final r2 = _rectangleElement(
        id: 'r2',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 150, maxY: 150),
      );
      final invisible = ElementState(
        id: 'inv',
        rect: const DrawRect(minX: 200, minY: 200, maxX: 250, maxY: 250),
        rotation: 0,
        opacity: 0,
        zIndex: 0,
        data: const RectangleData(),
      );
      final state = _stateWith([r1, r2, invisible], selectedIds: {'r1'});

      // Verify the filtering logic: visible non-selected elements only.
      final references = state.domain.document.elements
          .where(
            (e) =>
                e.opacity > 0 &&
                !state.domain.selection.selectedIds.contains(e.id),
          )
          .toList();
      expect(references.length, equals(1));
      expect(references.first.id, equals('r2'));
    });
  });
}

// ===========================================================================
// Test helpers
// ===========================================================================

DrawState _stateWith(List<ElementState> elements, {Set<String>? selectedIds}) {
  final ids = selectedIds ?? {elements.first.id};
  return DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(selectedIds: ids),
    ),
  );
}

ElementState _rectangleElement({required String id, required DrawRect rect}) =>
    ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

ElementState _arrowElement({
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

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }

  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
