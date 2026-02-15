import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('ArrowPointOperation binding target lookup optimization', () {
    test('middle turning-point drag skips binding target queries', () {
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 190, y: 50),
        ],
      );
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 300, maxY: 120),
      );
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: [target, arrow],
        counter: counter,
      );
      final state = _stateWith(document, selectedIds: const {'arrow'});

      const operation = ArrowPointOperation();
      final context = operation.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'arrow',
          pointKind: ArrowPointKind.turning,
          pointIndex: 1,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: const DrawPoint(x: 100, y: 50),
      );

      counter.reset();
      operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 100, y: 100),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      expect(counter.value, 0);
    });

    test('endpoint drag still performs binding target query', () {
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 190, y: 50)],
      );
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 300, maxY: 120),
      );
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: [target, arrow],
        counter: counter,
      );
      final state = _stateWith(document, selectedIds: const {'arrow'});

      const operation = ArrowPointOperation();
      final context = operation.createContext(
        state: state,
        position: const DrawPoint(x: 10, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'arrow',
          pointKind: ArrowPointKind.turning,
          pointIndex: 0,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: const DrawPoint(x: 10, y: 50),
      );

      counter.reset();
      operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 30, y: 55),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      expect(counter.value, greaterThan(0));
    });

    test('addable-point drag skips binding target queries', () {
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 190, y: 50)],
      );
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 300, maxY: 120),
      );
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: [target, arrow],
        counter: counter,
      );
      final state = _stateWith(document, selectedIds: const {'arrow'});

      const operation = ArrowPointOperation();
      final context = operation.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'arrow',
          pointKind: ArrowPointKind.addable,
          pointIndex: 0,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: const DrawPoint(x: 100, y: 50),
      );

      counter.reset();
      operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 100, y: 120),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      expect(counter.value, 0);
    });
  });
}

class _CountingDocumentState extends DocumentState {
  _CountingDocumentState({required super.elements, required this.counter});

  final _HitTestCounter counter;

  @override
  void visitElementsAtPointTopDown(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor,
  ) {
    counter.value++;
    super.visitElementsAtPointTopDown(point, tolerance, visitor);
  }
}

class _HitTestCounter {
  var value = 0;

  void reset() {
    value = 0;
  }
}

DrawState _stateWith(
  DocumentState document, {
  required Set<String> selectedIds,
}) => DrawState(
  domain: DomainState(
    document: document,
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

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
