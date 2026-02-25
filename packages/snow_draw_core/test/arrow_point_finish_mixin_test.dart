import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
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
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('ArrowPointOperation finish/preview consistency', () {
    test('endpoint drag: preview rect matches finish rect', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 0, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
        currentPosition: const DrawPoint(x: 250, y: 100),
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

    test('mid-point drag: preview rect matches finish rect', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 200, y: 50),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
        currentPosition: const DrawPoint(x: 100, y: 120),
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
    });
  });

  group('ArrowPointOperation identity handling', () {
    test('no-change finish returns idle', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
      expect(
        result.domain.document.getElementById('a1')!.rect,
        equals(arrow.rect),
      );
    });

    test('no-change preview returns EditPreview.none', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
  });

  group('ArrowPointOperation point deletion', () {
    test('finish deletes mid-point when shouldDelete is true', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 200, y: 50),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
        currentPosition: const DrawPoint(x: 10, y: 50),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final transform = update.transform as ArrowPointTransform;
      expect(transform.shouldDelete, isTrue);

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finishedArrow = result.domain.document.getElementById('a1')!;
      final finishedData = finishedArrow.data as ArrowData;
      expect(finishedData.points.length, equals(2));
    });

    test('preview keeps all points even when shouldDelete is true', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 200, y: 50),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
        currentPosition: const DrawPoint(x: 10, y: 50),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final transform = update.transform as ArrowPointTransform;
      expect(transform.shouldDelete, isTrue);

      final preview = op.buildPreview(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final previewEl = preview.previewElementsById['a1']!;
      final previewData = previewEl.data as ArrowData;
      expect(previewData.points.length, equals(3));
    });

    test('double-click delete on start triggers immediate deletion', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 80),
          DrawPoint(x: 200, y: 50),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 80),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 1,
          isDoubleClick: true,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 100, y: 80),
      );

      expect(t0.shouldDelete, isTrue);
      expect(t0.hasChanges, isTrue);

      final result = op.finish(state: state, context: ctx, transform: t0);
      final finishedArrow = result.domain.document.getElementById('a1')!;
      final finishedData = finishedArrow.data as ArrowData;
      expect(finishedData.points.length, equals(2));
    });
  });

  group('ArrowPointOperation point insertion', () {
    test('addable point inserts after threshold', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 105, y: 50),
        params: const ArrowPointOperationParams(
          elementId: 'a1',
          pointKind: ArrowPointKind.addable,
          pointIndex: 0,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 105, y: 50),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 105, y: 100),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finishedArrow = result.domain.document.getElementById('a1')!;
      final finishedData = finishedArrow.data as ArrowData;
      expect(finishedData.points.length, equals(3));
    });
  });

  group('ArrowPointOperation binding handling', () {
    test('dragging non-endpoint preserves existing bindings', () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: 190, minY: 40, maxX: 280, maxY: 120),
      );
      const binding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      );
      final arrow = _arrowElement(
        id: 'a1',
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 190, y: 80),
        ],
        endBinding: binding,
      );
      final state = _stateWith([target, arrow], selectedIds: const {'a1'});

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

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finishedArrow = result.domain.document.getElementById('a1')!;
      final finishedData = finishedArrow.data as ArrowData;
      expect(finishedData.endBinding, equals(binding));
    });
  });

  group('ArrowPointOperation elbow arrows', () {
    test('elbow endpoint drag: preview matches finish rect', () {
      final arrow = _arrowElement(
        id: 'e1',
        arrowType: ArrowType.elbow,
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 100, y: 150),
          DrawPoint(x: 200, y: 150),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'e1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 200, y: 150),
        params: const ArrowPointOperationParams(
          elementId: 'e1',
          pointKind: ArrowPointKind.turning,
          pointIndex: 3,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 200, y: 150),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 250, y: 200),
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

      final previewEl = preview.previewElementsById['e1']!;
      final finishEl = finished.domain.document.getElementById('e1')!;
      expect(previewEl.rect, equals(finishEl.rect));
    });

    test('elbow segment drag produces valid geometry', () {
      final arrow = _arrowElement(
        id: 'e1',
        arrowType: ArrowType.elbow,
        points: const [
          DrawPoint(x: 10, y: 50),
          DrawPoint(x: 100, y: 50),
          DrawPoint(x: 100, y: 150),
          DrawPoint(x: 200, y: 150),
        ],
      );
      final state = _stateWith([arrow], selectedIds: const {'e1'});

      const op = ArrowPointOperation();
      final ctx = op.createContext(
        state: state,
        position: const DrawPoint(x: 100, y: 100),
        params: const ArrowPointOperationParams(
          elementId: 'e1',
          pointKind: ArrowPointKind.addable,
          pointIndex: 1,
        ),
      );
      final t0 = op.initialTransform(
        state: state,
        context: ctx,
        startPosition: const DrawPoint(x: 100, y: 100),
      );
      final update = op.update(
        state: state,
        context: ctx,
        transform: t0,
        currentPosition: const DrawPoint(x: 130, y: 100),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );

      final result = op.finish(
        state: state,
        context: ctx,
        transform: update.transform,
      );
      final finishedArrow = result.domain.document.getElementById('e1')!;
      final finishedData = finishedArrow.data as ArrowData;
      expect(finishedData.points.length, greaterThanOrEqualTo(2));
      expect(result.application.interaction, isA<IdleState>());
    });
  });

  group('ArrowPointOperation cancel', () {
    test('cancel returns to idle without modifying elements', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

      const op = ArrowPointOperation();
      final result = op.cancel(state: state);
      expect(result.application.interaction, isA<IdleState>());
      expect(
        result.domain.document.getElementById('a1')!.rect,
        equals(arrow.rect),
      );
    });
  });

  group('ArrowPointOperation selection preview', () {
    test('preview includes selection preview', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 10, y: 50), DrawPoint(x: 200, y: 50)],
      );
      final state = _stateWith([arrow], selectedIds: const {'a1'});

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
      expect(preview.selectionPreview, isNotNull);
    });
  });
}

DrawState _stateWith(
  List<ElementState> elements, {
  required Set<String> selectedIds,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
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
  ArrowType arrowType = ArrowType.straight,
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
      arrowType: arrowType,
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
