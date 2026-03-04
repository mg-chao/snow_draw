import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/edit/move/move_operation.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('MoveOperation arrow binding lifecycle integration', () {
    test(
      'moving bound arrow with its bindable target preserves endpoint binding',
      () {
        final rect = _rectangleElement(
          id: 'rect-shared',
          rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 200),
          zIndex: 0,
        );
        final arrow = _arrowElement(
          id: 'arrow-shared',
          points: const <DrawPoint>[
            DrawPoint(x: 220, y: 150),
            DrawPoint(x: 320, y: 190),
          ],
          zIndex: 1,
          startBinding: const ArrowBinding(
            elementId: 'rect-shared',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[rect, arrow],
          selectedIds: <String>{rect.id, arrow.id},
        );

        final next = _moveSelection(
          state: state,
          startPosition: const DrawPoint(x: 210, y: 160),
          currentPosition: const DrawPoint(x: 260, y: 185),
        );
        final movedArrow = next.domain.document.getElementById(arrow.id)!;
        final movedData = movedArrow.data as ArrowData;

        expect(movedData.startBinding, isNotNull);
        expect(movedData.startBinding!.elementId, rect.id);
      },
    );

    test('moving bound arrow alone prunes endpoint bindings', () {
      final rect = _rectangleElement(
        id: 'rect-anchor',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 200),
        zIndex: 0,
      );
      final arrow = _arrowElement(
        id: 'arrow-alone',
        points: const <DrawPoint>[
          DrawPoint(x: 220, y: 150),
          DrawPoint(x: 320, y: 190),
        ],
        zIndex: 1,
        startBinding: const ArrowBinding(
          elementId: 'rect-anchor',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
      );
      final state = _stateWithElements(
        <ElementState>[rect, arrow],
        selectedIds: <String>{arrow.id},
      );

      final next = _moveSelection(
        state: state,
        startPosition: const DrawPoint(x: 250, y: 150),
        currentPosition: const DrawPoint(x: 300, y: 180),
      );
      final movedArrow = next.domain.document.getElementById(arrow.id)!;
      final movedData = movedArrow.data as ArrowData;

      expect(movedData.startBinding, isNull);
      expect(movedData.endBinding, isNull);
    });

    test(
      'moving bindable target alone recomputes connected arrow endpoint',
      () {
        final rect = _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 200),
          zIndex: 0,
        );
        final arrow = _arrowElement(
          id: 'arrow-follow',
          points: const <DrawPoint>[
            DrawPoint(x: 220, y: 150),
            DrawPoint(x: 320, y: 190),
          ],
          zIndex: 1,
          startBinding: const ArrowBinding(
            elementId: 'rect-target',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );
        final beforeArrowPoints = ArrowGeometry.resolveWorldPoints(
          rect: arrow.rect,
          normalizedPoints: (arrow.data as ArrowData).points,
        );
        final state = _stateWithElements(
          <ElementState>[rect, arrow],
          selectedIds: <String>{rect.id},
        );

        final next = _moveSelection(
          state: state,
          startPosition: const DrawPoint(x: 160, y: 150),
          currentPosition: const DrawPoint(x: 210, y: 180),
        );
        final movedArrow = next.domain.document.getElementById(arrow.id)!;
        final movedData = movedArrow.data as ArrowData;
        final afterArrowPoints = ArrowGeometry.resolveWorldPoints(
          rect: movedArrow.rect,
          normalizedPoints: movedData.points,
        );

        expect(movedData.startBinding, isNotNull);
        expect(movedData.startBinding!.elementId, rect.id);
        expect(
          afterArrowPoints.first.distanceSquared(beforeArrowPoints.first),
          greaterThan(0),
        );
      },
    );
  });
}

DrawState _stateWithElements(
  List<ElementState> elements, {
  required Set<String> selectedIds,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

DrawState _moveSelection({
  required DrawState state,
  required DrawPoint startPosition,
  required DrawPoint currentPosition,
  EditModifiers modifiers = const EditModifiers(snapOverride: true),
}) {
  const operation = MoveOperation();
  final context = operation.createContext(
    state: state,
    position: startPosition,
    params: const MoveOperationParams(),
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
    currentPosition: currentPosition,
    modifiers: modifiers,
    config: DrawConfig.defaultConfig,
  );
  return operation.finish(
    state: state,
    context: context,
    transform: update.transform,
  );
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowBinding? startBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(points: normalized, startBinding: startBinding),
  );
}
