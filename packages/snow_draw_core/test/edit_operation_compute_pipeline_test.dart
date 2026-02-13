import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/move/move_operation.dart';
import 'package:snow_draw_core/draw/edit/preview/edit_preview.dart';
import 'package:snow_draw_core/draw/edit/resize/resize_operation.dart';
import 'package:snow_draw_core/draw/edit/rotate/rotate_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  // =========================================================================
  // Shared helpers
  // =========================================================================

  DrawState _stateWith(
    List<ElementState> elements, {
    Set<String>? selectedIds,
  }) {
    final ids = selectedIds ?? {elements.first.id};
    return DrawState(
      domain: DomainState(
        document: DocumentState(elements: elements),
        selection: SelectionState(selectedIds: ids),
      ),
    );
  }

  // =========================================================================
  // Move operation: finish + preview consistency
  // =========================================================================

  group('MoveOperation finish/preview pipeline', () {
    test('finish moves element and transitions to idle', () {
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
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final moved = result.domain.document.getElementById('r1')!;
      expect(moved.rect.centerX, closeTo(80, 0.01));
      expect(moved.rect.centerY, closeTo(60, 0.01));
      expect(result.application.interaction, isA<IdleState>());
    });

    test('preview matches finish geometry', () {
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
      final finishRect =
          finished.domain.document.getElementById('r1')!.rect;
      expect(previewRect, equals(finishRect));
    });

    test('identity transform returns idle without changes', () {
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
      final result = op.finish(
        state: state,
        context: ctx,
        transform: MoveTransform.zero,
      );

      expect(result.application.interaction, isA<IdleState>());
      expect(
        result.domain.document.getElementById('r1')!.rect,
        equals(element.rect),
      );
    });

    test('identity transform preview returns none', () {
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
      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: MoveTransform.zero,
      );

      expect(preview.previewElementsById, isEmpty);
    });

    test('move unbinds arrow elements', () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [
          DrawPoint(x: 10, y: 80),
          DrawPoint(x: 200, y: 80),
        ],
        startBinding: binding,
      );
      final state = _stateWith(
        [target, arrow],
        selectedIds: {'arrow'},
      );

      const op = MoveOperation();
      final ctx = op.createContext(
        state: state,
        position: arrow.center,
        params: const MoveOperationParams(),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: arrow.center,
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition:
            arrow.center.translate(const DrawPoint(x: 50, y: 0)),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final movedArrow = result.domain.document.getElementById('arrow')!;
      final data = movedArrow.data as ArrowData;
      expect(data.startBinding, isNull);
    });
  });

  // =========================================================================
  // Resize operation: finish + preview consistency
  // =========================================================================

  group('ResizeOperation finish/preview pipeline', () {
    test('finish resizes element and transitions to idle', () {
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
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final resized = result.domain.document.getElementById('r1')!;
      expect(resized.rect.width, greaterThan(100));
      expect(resized.rect.height, greaterThan(100));
      expect(result.application.interaction, isA<IdleState>());
    });

    test('preview matches finish geometry', () {
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
      final finishRect =
          finished.domain.document.getElementById('r1')!.rect;
      expect(previewRect, equals(finishRect));
    });

    test('incomplete transform returns idle without changes', () {
      final element = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
      );
      final state = _stateWith([element]);

      const op = ResizeOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 100),
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.bottomRight,
          selectionPadding: 0,
        ),
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: const ResizeTransform.incomplete(
          currentPosition: DrawPoint(x: 100, y: 100),
        ),
      );

      expect(result.application.interaction, isA<IdleState>());
      expect(
        result.domain.document.getElementById('r1')!.rect,
        equals(element.rect),
      );
    });

    test('resize unbinds arrow elements', () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [
          DrawPoint(x: 10, y: 80),
          DrawPoint(x: 200, y: 80),
        ],
        startBinding: binding,
        startIsSpecial: true,
      );
      final state = _stateWith(
        [target, arrow],
        selectedIds: {'arrow'},
      );

      const op = ResizeOperation();
      final handlePos =
          DrawPoint(x: arrow.rect.maxX, y: arrow.rect.centerY);
      final ctx = op.createContext(
        state: state,
        position: handlePos,
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.right,
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
        currentPosition:
            handlePos.translate(const DrawPoint(x: 48, y: 0)),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final resizedArrow =
          result.domain.document.getElementById('arrow')!;
      final data = resizedArrow.data as ArrowData;
      expect(data.startBinding, isNull);
    });
  });

  // =========================================================================
  // Rotate operation: finish + preview consistency
  // =========================================================================

  group('RotateOperation finish/preview pipeline', () {
    test('finish rotates element and transitions to idle', () {
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
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final rotated = result.domain.document.getElementById('r1')!;
      expect(rotated.rotation.abs(), greaterThan(0.1));
      expect(result.application.interaction, isA<IdleState>());
    });

    test('preview matches finish geometry', () {
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
      final finishEl =
          finished.domain.document.getElementById('r1')!;
      expect(previewEl.rect, equals(finishEl.rect));
      expect(previewEl.rotation, closeTo(finishEl.rotation, 0.001));
    });

    test('identity transform returns idle without changes', () {
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
      final result = op.finish(
        state: state,
        context: ctx,
        transform: RotateTransform.zero,
      );

      expect(result.application.interaction, isA<IdleState>());
      expect(
        result.domain.document.getElementById('r1')!.rotation,
        equals(0.0),
      );
    });

    test('rotate unbinds arrow elements', () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [
          DrawPoint(x: 10, y: 80),
          DrawPoint(x: 200, y: 80),
        ],
        startBinding: binding,
        startIsSpecial: true,
      );
      final state = _stateWith(
        [target, arrow],
        selectedIds: {'arrow'},
      );

      const op = RotateOperation();
      final center = arrow.rect.center;
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

      final rotatedArrow =
          result.domain.document.getElementById('arrow')!;
      final data = rotatedArrow.data as ArrowData;
      expect(data.startBinding, isNull);
    });
  });

  // =========================================================================
  // Multi-select overlay updates
  // =========================================================================

  group('Multi-select overlay updates', () {
    test('move updates multi-select overlay bounds', () {
      final r1 = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 50, maxY: 50),
      );
      final r2 = _rectangleElement(
        id: 'r2',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 150, maxY: 150),
      );
      final state = _stateWith([r1, r2], selectedIds: {'r1', 'r2'});

      const op = MoveOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 75, y: 75),
        params: const MoveOperationParams(),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 75, y: 75),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 95, y: 95),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final overlay =
          result.application.selectionOverlay.multiSelectOverlay;
      expect(overlay, isNotNull);
      expect(overlay!.bounds.centerX, greaterThan(75));
    });

    test('rotate updates multi-select overlay rotation', () {
      final r1 = _rectangleElement(
        id: 'r1',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 50, maxY: 50),
      );
      final r2 = _rectangleElement(
        id: 'r2',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 150, maxY: 150),
      );
      final state = _stateWith([r1, r2], selectedIds: {'r1', 'r2'});

      const op = RotateOperation();
      final center = const DrawRect(
        minX: 0,
        minY: 0,
        maxX: 150,
        maxY: 150,
      ).center;
      final startPos = DrawPoint(x: center.x + 80, y: center.y);
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
        currentPosition: DrawPoint(x: center.x, y: center.y + 80),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );

      final overlay =
          result.application.selectionOverlay.multiSelectOverlay;
      expect(overlay, isNotNull);
      expect(overlay!.rotation.abs(), greaterThan(0.1));
    });
  });
}

// ===========================================================================
// Test helpers
// ===========================================================================

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
}) =>
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
  bool? startIsSpecial,
  bool? endIsSpecial,
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
      startIsSpecial: startIsSpecial,
      endIsSpecial: endIsSpecial,
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
