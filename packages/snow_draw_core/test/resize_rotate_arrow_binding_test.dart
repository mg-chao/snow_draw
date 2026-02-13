import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
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
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  test('resizing arrow clears bindings and stops follow-up updates', () {
    final target = _rectangleElement(
      id: 'target',
      rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
    );
    const startBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0, y: 0.5),
    );
    const endBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 1, y: 0.5),
    );
    final arrow = _arrowElement(
      id: 'arrow',
      points: const <DrawPoint>[
        DrawPoint(x: 120, y: 80),
        DrawPoint(x: 180, y: 120),
      ],
      startBinding: startBinding,
      endBinding: endBinding,
      startIsSpecial: true,
      endIsSpecial: true,
    );
    final state = DrawState(
      domain: DomainState(
        document: DocumentState(elements: [target, arrow]),
        selection: const SelectionState(selectedIds: {'arrow'}),
      ),
    );

    const operation = ResizeOperation();
    final handlePosition = DrawPoint(x: arrow.rect.maxX, y: arrow.rect.centerY);
    final context = operation.createContext(
      state: state,
      position: handlePosition,
      params: const ResizeOperationParams(
        resizeMode: ResizeMode.right,
        selectionPadding: 0,
      ),
    );
    final initialTransform = operation.initialTransform(
      state: state,
      context: context,
      startPosition: handlePosition,
    );
    final update = operation.update(
      state: state,
      context: context,
      transform: initialTransform,
      currentPosition: handlePosition.translate(const DrawPoint(x: 48, y: 0)),
      modifiers: const EditModifiers(),
      config: DrawConfig.defaultConfig,
    );
    final resizedState = operation.finish(
      state: state,
      context: context,
      transform: update.transform,
    );

    final resizedArrow = resizedState.domain.document.getElementById('arrow');
    expect(resizedArrow, isNotNull);
    final resizedData = resizedArrow!.data as ArrowData;
    expect(resizedData.startBinding, isNull);
    expect(resizedData.endBinding, isNull);
    expect(resizedData.startIsSpecial, isNull);
    expect(resizedData.endIsSpecial, isNull);

    final movedTarget = target.copyWith(
      rect: target.rect.translate(const DrawPoint(x: 48, y: 0)),
    );
    final bindingUpdates = ArrowBindingResolver.instance.resolve(
      baseElements: resizedState.domain.document.elementMap,
      updatedElements: {target.id: movedTarget},
      changedElementIds: {target.id},
      document: resizedState.domain.document,
    );
    expect(bindingUpdates.containsKey('arrow'), isFalse);
  });

  test('rotating arrow clears bindings and stops follow-up updates', () {
    final target = _rectangleElement(
      id: 'target',
      rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
    );
    const startBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0, y: 0.5),
    );
    const endBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 1, y: 0.5),
    );
    final arrow = _arrowElement(
      id: 'arrow',
      points: const <DrawPoint>[
        DrawPoint(x: 120, y: 80),
        DrawPoint(x: 180, y: 120),
      ],
      startBinding: startBinding,
      endBinding: endBinding,
      startIsSpecial: true,
      endIsSpecial: true,
    );
    final state = DrawState(
      domain: DomainState(
        document: DocumentState(elements: [target, arrow]),
        selection: const SelectionState(selectedIds: {'arrow'}),
      ),
    );

    const operation = RotateOperation();
    final center = arrow.rect.center;
    final startPosition = DrawPoint(x: center.x + 60, y: center.y);
    final context = operation.createContext(
      state: state,
      position: startPosition,
      params: const RotateOperationParams(),
    );
    final initialTransform = operation.initialTransform(
      state: state,
      context: context,
      startPosition: startPosition,
    );
    final update = operation.update(
      state: state,
      context: context,
      transform: initialTransform,
      currentPosition: DrawPoint(x: center.x, y: center.y + 60),
      modifiers: const EditModifiers(),
      config: DrawConfig.defaultConfig,
    );
    final rotatedState = operation.finish(
      state: state,
      context: context,
      transform: update.transform,
    );

    final rotatedArrow = rotatedState.domain.document.getElementById('arrow');
    expect(rotatedArrow, isNotNull);
    final rotatedData = rotatedArrow!.data as ArrowData;
    expect(rotatedData.startBinding, isNull);
    expect(rotatedData.endBinding, isNull);
    expect(rotatedData.startIsSpecial, isNull);
    expect(rotatedData.endIsSpecial, isNull);

    final movedTarget = target.copyWith(
      rect: target.rect.translate(const DrawPoint(x: 48, y: 0)),
    );
    final bindingUpdates = ArrowBindingResolver.instance.resolve(
      baseElements: rotatedState.domain.document.elementMap,
      updatedElements: {target.id: movedTarget},
      changedElementIds: {target.id},
      document: rotatedState.domain.document,
    );
    expect(bindingUpdates.containsKey('arrow'), isFalse);
  });
}

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

ElementState _rectangleElement({required String id, required DrawRect rect}) =>
    ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

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
