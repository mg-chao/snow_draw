import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';

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

    test('endpoint drag skips lookup when no bindable targets exist', () {
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 190, y: 50)],
      );
      final nonBindableArrow = _arrowElement(
        id: 'other-arrow',
        points: const [DrawPoint(x: 240, y: 60), DrawPoint(x: 320, y: 80)],
      ).copyWith(zIndex: 2);
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: [arrow, nonBindableArrow],
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

      expect(counter.value, 0);
    });

    test('endpoint drag with preferred binding skips spatial query', () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 140, maxY: 140),
      );
      final arrow = _arrowElement(
        id: 'arrow',
        points: const [DrawPoint(x: 80, y: 80), DrawPoint(x: 260, y: 80)],
        startBinding: const ArrowBinding(
          elementId: 'target',
          anchor: DrawPoint(x: 0.5, y: 0.5),
        ),
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
        position: const DrawPoint(x: 80, y: 80),
        params: const ArrowPointOperationParams(
          elementId: 'arrow',
          pointKind: ArrowPointKind.turning,
          pointIndex: 0,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: const DrawPoint(x: 80, y: 80),
      );

      counter.reset();
      operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 90, y: 92),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      expect(counter.value, 0);
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

    test(
      'arrow endpoint drag reuses binding target cache on medium movement',
      () {
        final arrow = _arrowElement(
          id: 'arrow',
          points: const [DrawPoint(x: 120, y: 160), DrawPoint(x: 320, y: 160)],
        );
        final target = _rectangleElement(
          id: 'target',
          rect: const DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
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
          position: const DrawPoint(x: 120, y: 160),
          params: const ArrowPointOperationParams(
            elementId: 'arrow',
            pointKind: ArrowPointKind.turning,
            pointIndex: 0,
          ),
        );
        final initialTransform = operation.initialTransform(
          state: state,
          context: context,
          startPosition: const DrawPoint(x: 120, y: 160),
        );

        counter.reset();
        final first = operation.update(
          state: state,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 209, y: 160),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final firstTransform = first.transform as ArrowPointTransform;
        final callsAfterFirstUpdate = counter.value;

        operation.update(
          state: state,
          context: context,
          transform: firstTransform,
          currentPosition: const DrawPoint(x: 217, y: 160),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final callsAfterSecondUpdate = counter.value;

        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
      },
    );

    test(
      'line endpoint drag reuses binding target cache on medium movement',
      () {
        final line = _lineElement(
          id: 'line',
          points: const [DrawPoint(x: 120, y: 160), DrawPoint(x: 320, y: 160)],
        );
        final target = _rectangleElement(
          id: 'target',
          rect: const DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
        );
        final counter = _HitTestCounter();
        final document = _CountingDocumentState(
          elements: [target, line],
          counter: counter,
        );
        final state = _stateWith(document, selectedIds: const {'line'});

        const operation = ArrowPointOperation();
        final context = operation.createContext(
          state: state,
          position: const DrawPoint(x: 120, y: 160),
          params: const ArrowPointOperationParams(
            elementId: 'line',
            pointKind: ArrowPointKind.turning,
            pointIndex: 0,
          ),
        );
        final initialTransform = operation.initialTransform(
          state: state,
          context: context,
          startPosition: const DrawPoint(x: 120, y: 160),
        );

        counter.reset();
        final first = operation.update(
          state: state,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 209, y: 160),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final firstTransform = first.transform as ArrowPointTransform;
        final callsAfterFirstUpdate = counter.value;

        operation.update(
          state: state,
          context: context,
          transform: firstTransform,
          currentPosition: const DrawPoint(x: 217, y: 160),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final callsAfterSecondUpdate = counter.value;

        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
      },
    );

    test('line endpoint drag re-evaluates candidate when '
        'prior lookup had no match', () {
      final line = _lineElement(
        id: 'line',
        points: const [DrawPoint(x: 120, y: 160), DrawPoint(x: 320, y: 160)],
      );
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
      );
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: [target, line],
        counter: counter,
      );
      final state = _stateWith(document, selectedIds: const {'line'});

      const operation = ArrowPointOperation();
      final context = operation.createContext(
        state: state,
        position: const DrawPoint(x: 120, y: 160),
        params: const ArrowPointOperationParams(
          elementId: 'line',
          pointKind: ArrowPointKind.turning,
          pointIndex: 0,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: const DrawPoint(x: 120, y: 160),
      );

      counter.reset();
      final first = operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 186, y: 170),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final firstTransform = first.transform as ArrowPointTransform;
      final callsAfterFirstUpdate = counter.value;

      final second = operation.update(
        state: state,
        context: context,
        transform: firstTransform,
        currentPosition: const DrawPoint(x: 190, y: 170),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final callsAfterSecondUpdate = counter.value;
      final secondTransform = second.transform as ArrowPointTransform;

      expect(firstTransform.startBinding, isNull);
      expect(secondTransform.startBinding, isNotNull);
      expect(callsAfterFirstUpdate, greaterThan(0));
      expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
    });

    test(
      'line endpoint drag refreshes empty cache when entering bind range',
      () {
        final line = _lineElement(
          id: 'line',
          points: const [DrawPoint(x: 120, y: 160), DrawPoint(x: 320, y: 160)],
        );
        final target = _rectangleElement(
          id: 'target',
          rect: const DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
        );
        final counter = _HitTestCounter();
        final document = _CountingDocumentState(
          elements: [target, line],
          counter: counter,
        );
        final state = _stateWith(document, selectedIds: const {'line'});

        const operation = ArrowPointOperation();
        final context = operation.createContext(
          state: state,
          position: const DrawPoint(x: 120, y: 160),
          params: const ArrowPointOperationParams(
            elementId: 'line',
            pointKind: ArrowPointKind.turning,
            pointIndex: 0,
          ),
        );
        final initialTransform = operation.initialTransform(
          state: state,
          context: context,
          startPosition: const DrawPoint(x: 120, y: 160),
        );

        counter.reset();
        final first = operation.update(
          state: state,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 180, y: 170),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final firstTransform = first.transform as ArrowPointTransform;
        final callsAfterFirstUpdate = counter.value;

        final second = operation.update(
          state: state,
          context: context,
          transform: firstTransform,
          currentPosition: const DrawPoint(x: 192, y: 170),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final callsAfterSecondUpdate = counter.value;
        final secondTransform = second.transform as ArrowPointTransform;

        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, greaterThan(0));
        expect(secondTransform.startBinding, isNotNull);
      },
    );
  });
}

class _CountingDocumentState extends DocumentState {
  _CountingDocumentState({required super.elements, required this.counter});

  final _HitTestCounter counter;

  @override
  void visitArrowBindableElementsAtPoint(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor, {
    String? excludedElementId,
  }) {
    counter.value++;
    super.visitArrowBindableElementsAtPoint(
      point,
      tolerance,
      visitor,
      excludedElementId: excludedElementId,
    );
  }
}

class _HitTestCounter {
  var value = 0;

  void reset() => value = 0;
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

ElementState _lineElement({
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
    data: LineData(points: normalized),
  );
}

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
