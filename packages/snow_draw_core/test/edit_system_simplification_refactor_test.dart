/// Pre-refactoring tests that lock down behavior of the edit system
/// before simplifying duplicated patterns:
///
/// 1. computeResult validation + identity guard (shared across
///    Move/Resize/Rotate).
/// 2. Private _resolveReferenceElements wrappers (Move/Resize).
/// 3. Snapshot building helpers (buildMoveSnapshots, etc.).
/// 4. Context creation boilerplate (selection bounds, IDs, versions).
///
/// Each test captures the exact output of the current code so that
/// after refactoring we can verify nothing changed.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_helpers.dart';
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
  // 1. computeResult returns null for identity transforms
  // =========================================================================

  group('computeResult identity guard', () {
    test('MoveOperation: zero displacement returns null preview', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

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

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: t0,
      );
      expect(preview.previewElementsById, isEmpty);
    });

    test('RotateOperation: zero angle returns null preview', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = RotateOperation();
      final center = el.rect.center;
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

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: t0,
      );
      expect(preview.previewElementsById, isEmpty);
    });

    test('ResizeOperation: incomplete transform returns null preview', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = ResizeOperation();
      final handlePos = DrawPoint(x: el.rect.maxX, y: el.rect.maxY);
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

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: t0,
      );
      expect(preview.previewElementsById, isEmpty);
    });
  });

  // =========================================================================
  // 2. computeResult validation: empty snapshots / empty selection
  // =========================================================================

  group('computeResult validation guard', () {
    test('MoveEditContext with empty snapshots is invalid', () {
      final ctx = MoveEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
        selectedIdsAtStart: const {'r1'},
        selectionVersion: 0,
        elementsVersion: 0,
        elementSnapshots: const {},
      );
      expect(EditValidation.isValidContext(ctx), isFalse);
    });

    test('ResizeEditContext with empty selection is invalid', () {
      final ctx = ResizeEditContext(
        startPosition: const DrawPoint(x: 0, y: 0),
        startBounds: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
        selectedIdsAtStart: const {},
        selectionVersion: 0,
        elementsVersion: 0,
        resizeMode: ResizeMode.bottomRight,
        handleOffset: const DrawPoint(x: 0, y: 0),
        rotation: 0,
        elementSnapshots: const {
          'r1': ElementResizeSnapshot(
            rect: DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
            rotation: 0,
          ),
        },
      );
      expect(EditValidation.isValidContext(ctx), isFalse);
    });

    test('RotateEditContext with zero-size bounds is invalid', () {
      expect(
        EditValidation.isValidBounds(
          const DrawRect(minX: 5, minY: 5, maxX: 5, maxY: 5),
        ),
        isFalse,
      );
    });
  });

  // =========================================================================
  // 3. Snapshot building helpers produce correct data
  // =========================================================================

  group('Snapshot building helpers', () {
    test('buildMoveSnapshots captures element centers', () {
      final el = _rect('r1');
      final snapshots = buildMoveSnapshots([el]);
      expect(snapshots, hasLength(1));
      expect(snapshots['r1']!.center, equals(el.rect.center));
    });

    test('buildResizeSnapshots captures rect and rotation', () {
      final el = ElementState(
        id: 'r1',
        rect: const DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 120),
        rotation: 0.5,
        opacity: 1,
        zIndex: 0,
        data: const RectangleData(),
      );
      final snapshots = buildResizeSnapshots([el]);
      expect(snapshots, hasLength(1));
      expect(snapshots['r1']!.rect, equals(el.rect));
      expect(snapshots['r1']!.rotation, equals(0.5));
    });

    test('buildRotateSnapshots captures center and rotation', () {
      final el = ElementState(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
        rotation: 1.2,
        opacity: 1,
        zIndex: 0,
        data: const RectangleData(),
      );
      final snapshots = buildRotateSnapshots([el]);
      expect(snapshots, hasLength(1));
      expect(snapshots['r1']!.center, equals(el.rect.center));
      expect(snapshots['r1']!.rotation, equals(1.2));
    });
  });

  // =========================================================================
  // 4. resolveReferenceElements filters correctly
  // =========================================================================

  group('resolveReferenceElements', () {
    test('excludes selected elements', () {
      final r1 = _rect('r1');
      final r2 = _rectAt(
        'r2',
        const DrawRect(minX: 200, minY: 200, maxX: 300, maxY: 300),
      );
      final state = _stateWith([r1, r2]);

      final refs = resolveReferenceElements(state, {'r1'});
      expect(refs.length, equals(1));
      expect(refs.first.id, equals('r2'));
    });

    test('excludes invisible elements', () {
      final r1 = _rect('r1');
      final invisible = ElementState(
        id: 'inv',
        rect: const DrawRect(minX: 200, minY: 200, maxX: 300, maxY: 300),
        rotation: 0,
        opacity: 0,
        zIndex: 0,
        data: const RectangleData(),
      );
      final state = _stateWith([r1, invisible]);

      final refs = resolveReferenceElements(state, {'r1'});
      expect(refs, isEmpty);
    });

    test('returns all visible non-selected elements', () {
      final r1 = _rect('r1');
      final r2 = _rectAt(
        'r2',
        const DrawRect(minX: 200, minY: 200, maxX: 300, maxY: 300),
      );
      final r3 = _rectAt(
        'r3',
        const DrawRect(minX: 400, minY: 400, maxX: 500, maxY: 500),
      );
      final state = _stateWith([r1, r2, r3]);

      final refs = resolveReferenceElements(state, {'r1'});
      expect(refs.length, equals(2));
      final ids = refs.map((e) => e.id).toSet();
      expect(ids, containsAll(['r2', 'r3']));
    });
  });

  // =========================================================================
  // 5. Context creation captures correct state
  // =========================================================================

  group('Context creation captures correct state', () {
    test('MoveOperation context captures selection version', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = MoveOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 50, y: 50),
        params: const MoveOperationParams(),
      );
      expect(
        ctx.selectionVersion,
        equals(state.domain.selection.selectionVersion),
      );
      expect(
        ctx.elementsVersion,
        equals(state.domain.document.elementsVersion),
      );
      expect(ctx.selectedIdsAtStart, equals({'r1'}));
    });

    test('ResizeOperation context captures resize mode', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = ResizeOperation();
      final ctx = op.createContext(
        state: state,
        position: DrawPoint(x: el.rect.maxX, y: el.rect.maxY),
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.topLeft,
          selectionPadding: 0,
        ),
      );
      final typedCtx = ctx as ResizeEditContext;
      expect(typedCtx.resizeMode, equals(ResizeMode.topLeft));
    });

    test('RotateOperation context captures base rotation', () {
      final el = ElementState(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
        rotation: 0.7,
        opacity: 1,
        zIndex: 0,
        data: const RectangleData(),
      );
      final state = _stateWith([el]);

      const op = RotateOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 110, y: 50),
        params: const RotateOperationParams(),
      );
      final typedCtx = ctx as RotateEditContext;
      expect(typedCtx.baseRotation, equals(0.7));
    });
  });

  // =========================================================================
  // 6. Full round-trip: update → preview → finish consistency
  // =========================================================================

  group('Full round-trip consistency after refactoring', () {
    test('move: displaced element center matches expected offset', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

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
        currentPosition: const DrawPoint(x: 70, y: 90),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final movedEl = finished.domain.document.getElementById('r1')!;
      // dx=20, dy=40 from original center (50,50)
      expect(movedEl.rect.centerX, closeTo(70, 0.01));
      expect(movedEl.rect.centerY, closeTo(90, 0.01));
    });

    test('resize: element grows when handle dragged outward', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = ResizeOperation();
      final handlePos = DrawPoint(x: el.rect.maxX, y: el.rect.maxY);
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
        currentPosition: const DrawPoint(x: 200, y: 200),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final resized = finished.domain.document.getElementById('r1')!;
      expect(resized.rect.width, greaterThan(el.rect.width));
      expect(resized.rect.height, greaterThan(el.rect.height));
    });

    test('rotate: element rotation changes after drag', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = RotateOperation();
      final center = el.rect.center;
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

      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final rotated = finished.domain.document.getElementById('r1')!;
      expect(rotated.rotation.abs(), greaterThan(0.1));
    });

    test('arrow point: endpoint drag changes rect', () {
      final arrow = _arrow('a1', const [
        DrawPoint(x: 10, y: 50),
        DrawPoint(x: 200, y: 50),
      ]);
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
      expect(finishEl.rect.maxX, greaterThan(arrow.rect.maxX));
    });
  });

  // =========================================================================
  // 7. Multi-element operations
  // =========================================================================

  group('Multi-element operations', () {
    test('move: all selected elements move by same offset', () {
      final r1 = _rect('r1');
      final r2 = _rectAt(
        'r2',
        const DrawRect(minX: 200, minY: 200, maxX: 300, maxY: 300),
      );
      final state = _stateWith([r1, r2], selectedIds: {'r1', 'r2'});

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
        currentPosition: const DrawPoint(x: 60, y: 70),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final finished = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final m1 = finished.domain.document.getElementById('r1')!;
      final m2 = finished.domain.document.getElementById('r2')!;
      // Both should move by dx=10, dy=20
      expect(m1.rect.centerX, closeTo(60, 0.01));
      expect(m1.rect.centerY, closeTo(70, 0.01));
      expect(m2.rect.centerX, closeTo(260, 0.01));
      expect(m2.rect.centerY, closeTo(270, 0.01));
    });
  });

  // =========================================================================
  // 8. Finish transitions to idle
  // =========================================================================

  group('Finish transitions to idle', () {
    test('move finish transitions to idle', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

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
        currentPosition: const DrawPoint(x: 80, y: 80),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      expect(result.application.interaction, isA<IdleState>());
    });

    test('resize finish transitions to idle', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = ResizeOperation();
      final ctx = op.createContext(
        state: state,
        position: DrawPoint(x: el.rect.maxX, y: el.rect.maxY),
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.bottomRight,
          selectionPadding: 0,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: DrawPoint(x: el.rect.maxX, y: el.rect.maxY),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 150, y: 150),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      expect(result.application.interaction, isA<IdleState>());
    });

    test('rotate finish transitions to idle', () {
      final el = _rect('r1');
      final state = _stateWith([el]);

      const op = RotateOperation();
      final center = el.rect.center;
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

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      expect(result.application.interaction, isA<IdleState>());
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

ElementState _rect(String id) => ElementState(
  id: id,
  rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

ElementState _rectAt(String id, DrawRect rect) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

ElementState _arrow(String id, List<DrawPoint> points) {
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
    data: ArrowData(points: normalized),
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
