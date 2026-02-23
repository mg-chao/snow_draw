import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/apply/edit_apply.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/core/edit_validation.dart';
import 'package:snow_draw_core/draw/edit/resize/resize_operation.dart';
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
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  group('replaceElementsById', () {
    test('small list: applies valid change, ignores ghost', () {
      final elements = List.generate(5, (i) => _element('e$i'));
      final replacement = elements[2].copyWith(
        rect: const DrawRect(minX: 50, minY: 50, maxX: 60, maxY: 60),
      );
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'e2': replacement, 'ghost': _element('ghost')},
      );

      expect(result.length, elements.length);
      expect(identical(result[2], replacement), isTrue);
      expect(result.map((e) => e.id).toList(), ['e0', 'e1', 'e2', 'e3', 'e4']);
    });

    test('large list: applies valid change, ignores ghost', () {
      final elements = List.generate(200, (i) => _element('el$i'));
      final replacement = elements[100].copyWith(
        rect: const DrawRect(minX: 999, minY: 999, maxX: 1000, maxY: 1000),
      );
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {'el100': replacement, 'ghost': _element('ghost')},
      );

      expect(result.length, 200);
      expect(identical(result[100], replacement), isTrue);
      expect(result[100].rect.minX, 999);
    });

    test('all ghost IDs return same list instance', () {
      final elements = List.generate(200, (i) => _element('el$i'));
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: {
          'ghost1': _element('ghost1'),
          'ghost2': _element('ghost2'),
        },
      );

      expect(identical(result, elements), isTrue);
    });

    test('more replacements than elements applies valid IDs only', () {
      final elements = List.generate(3, (i) => _element('e$i'));
      final replacements = <String, ElementState>{
        for (var i = 0; i < elements.length; i++)
          'e$i': elements[i].copyWith(
            rect: DrawRect(
              minX: i * 10.0,
              minY: i * 10.0,
              maxX: i * 10.0 + 10,
              maxY: i * 10.0 + 10,
            ),
          ),
        'e3': _element('e3'),
        'e4': _element('e4'),
      };
      final result = EditApply.replaceElementsById(
        elements: elements,
        replacementsById: replacements,
      );

      expect(result.length, 3);
      expect(result[0].rect.minX, 0);
      expect(result[1].rect.minX, 10);
      expect(result[2].rect.minX, 20);
    });
  });

  group('ResizeTransform.isIdentity', () {
    test('incomplete transform is identity', () {
      const t = ResizeTransform.incomplete(
        currentPosition: DrawPoint(x: 10, y: 10),
      );
      expect(t.isIdentity, isTrue);
    });

    test('scale 1.0/1.0 is identity', () {
      const t = ResizeTransform.complete(
        currentPosition: DrawPoint(x: 10, y: 10),
        newSelectionBounds: DrawRect(maxX: 100, maxY: 100),
        scaleX: 1,
        scaleY: 1,
        anchor: DrawPoint.zero,
      );
      expect(t.isIdentity, isTrue);
    });

    test('non-unit scale is not identity', () {
      const t = ResizeTransform.complete(
        currentPosition: DrawPoint(x: 10, y: 10),
        newSelectionBounds: DrawRect(maxX: 200, maxY: 200),
        scaleX: 2,
        scaleY: 2,
        anchor: DrawPoint.zero,
      );
      expect(t.isIdentity, isFalse);
    });

    test('resize operation: scale 1.0 with same bounds returns idle', () {
      final element = _element(
        'r1',
        rect: const DrawRect(maxX: 100, maxY: 100),
      );
      final state = _stateWith([element]);

      const op = ResizeOperation();
      final ctx = op.createContext(
        state: state,
        position: DrawPoint(x: element.rect.maxX, y: element.rect.maxY),
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.bottomRight,
          selectionPadding: 0,
        ),
      );
      const transform = ResizeTransform.complete(
        currentPosition: DrawPoint(x: 100, y: 100),
        newSelectionBounds: DrawRect(maxX: 100, maxY: 100),
        scaleX: 1,
        scaleY: 1,
        anchor: DrawPoint.zero,
      );
      final result = op.finish(
        state: state,
        context: ctx,
        transform: transform,
      );

      expect(result.application.interaction, isA<IdleState>());
      expect(
        result.domain.document.getElementById('r1')!.rect,
        equals(element.rect),
      );
    });
  });

  group('ArrowPointEditContext.hasSnapshots', () {
    test('returns true when initialPoints are present', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 0, y: 50), DrawPoint(x: 200, y: 50)],
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

      expect(ctx.hasSnapshots, isTrue);
    });
  });

  group('ArrowPointOperation round-trip', () {
    test('endpoint drag: preview and finish produce same rect', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 0, y: 50), DrawPoint(x: 200, y: 50)],
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
  });

  group('EditValidation with ArrowPointEditContext', () {
    test('isValidContext returns true for valid arrow point context', () {
      final arrow = _arrowElement(
        id: 'a1',
        points: const [DrawPoint(x: 0, y: 50), DrawPoint(x: 200, y: 50)],
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

      expect(EditValidation.isValidContext(ctx), isTrue);
    });
  });
}

ElementState _element(String id, {DrawRect? rect}) => ElementState(
  id: id,
  rect: rect ?? const DrawRect(maxX: 10, maxY: 10),
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

DrawState _stateWith(List<ElementState> elements, {Set<String>? selectedIds}) {
  assert(
    elements.isNotEmpty,
    'elements must contain at least one element for default selection',
  );
  return DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(
        selectedIds: selectedIds ?? {elements.first.id},
      ),
    ),
  );
}

DrawRect _rectForPoints(List<DrawPoint> points) {
  assert(points.isNotEmpty, 'points must not be empty');

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

  return DrawRect(
    minX: minX,
    minY: minY,
    maxX: maxX == minX ? minX + 1 : maxX,
    maxY: maxY == minY ? minY + 1 : maxY,
  );
}
