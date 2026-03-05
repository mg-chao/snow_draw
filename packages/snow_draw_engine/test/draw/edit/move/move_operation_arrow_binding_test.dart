import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/edit/move/move_operation.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/application_state.dart';
import 'package:snow_draw_engine/draw/models/camera_state.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/models/view_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
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

    test(
      'moving bindable after dual-bound elbow creation reroutes without stale segments',
      () {
        final startRect = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(
            minX: 94.17096401143294,
            minY: 50.78697730687034,
            maxX: 213.57967656368623,
            maxY: 217.17530955324455,
          ),
          zIndex: 0,
        );
        final endRect = _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(
            minX: 484.0196262072371,
            minY: -81.60597806639348,
            maxX: 618.6304458255274,
            maxY: 3.094218004920748,
          ),
          zIndex: 1,
        );
        final creationState = DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: <ElementState>[startRect, endRect],
            ),
          ),
          application: ApplicationState.initial(
            view: ViewState(camera: const CameraState()),
          ),
        );
        final createdArrow = _createElbowArrowFromCreation(
          state: creationState,
          startPosition: const DrawPoint(
            x: 187.77879269089954,
            y: 95.51675234685601,
          ),
          midPosition: const DrawPoint(
            x: 262.51927206478337,
            y: 101.4123258443541,
          ),
          endPosition: const DrawPoint(
            x: 517.6004822906378,
            y: -32.43569975244228,
          ),
        );
        final movingState = _stateWithElements(
          <ElementState>[startRect, endRect, createdArrow],
          selectedIds: <String>{startRect.id},
        );

        final moved = _moveSelection(
          state: movingState,
          startPosition: const DrawPoint(
            x: 153.8753202875596,
            y: 133.98114343005745,
          ),
          currentPosition: const DrawPoint(
            x: 283.87532028755957,
            y: 163.98114343005745,
          ),
        );
        final movedArrow = moved.domain.document.getElementById(
          createdArrow.id,
        )!;
        final movedData = movedArrow.data as ArrowData;
        final movedPoints = ArrowGeometry.resolveWorldPoints(
          rect: movedArrow.rect,
          normalizedPoints: movedData.points,
        );

        expect(movedData.startBinding, isNotNull);
        expect(movedData.startBinding!.elementId, startRect.id);
        expect(movedData.endBinding, isNotNull);
        expect(movedData.endBinding!.elementId, endRect.id);
        expect(movedPoints.length, greaterThanOrEqualTo(3));
        for (var index = 1; index < movedPoints.length; index += 1) {
          final dx = (movedPoints[index].x - movedPoints[index - 1].x).abs();
          final dy = (movedPoints[index].y - movedPoints[index - 1].y).abs();
          expect(dx <= 1e-6 || dy <= 1e-6, isTrue);
        }
        for (var index = 2; index < movedPoints.length; index += 1) {
          final prevDx = movedPoints[index - 1].x - movedPoints[index - 2].x;
          final prevDy = movedPoints[index - 1].y - movedPoints[index - 2].y;
          final nextDx = movedPoints[index].x - movedPoints[index - 1].x;
          final nextDy = movedPoints[index].y - movedPoints[index - 1].y;
          final prevVertical = prevDx.abs() <= 1e-6 && prevDy.abs() > 1e-6;
          final nextVertical = nextDx.abs() <= 1e-6 && nextDy.abs() > 1e-6;
          final prevHorizontal = prevDy.abs() <= 1e-6 && prevDx.abs() > 1e-6;
          final nextHorizontal = nextDy.abs() <= 1e-6 && nextDx.abs() > 1e-6;
          if (prevVertical && nextVertical) {
            expect(prevDy * nextDy, greaterThanOrEqualTo(0));
          }
          if (prevHorizontal && nextHorizontal) {
            expect(prevDx * nextDx, greaterThanOrEqualTo(0));
          }
        }
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

ElementState _createElbowArrowFromCreation({
  required DrawState state,
  required DrawPoint startPosition,
  required DrawPoint midPosition,
  required DrawPoint endPosition,
}) {
  const strategy = ArrowCreationStrategy();
  final start = strategy.start(
    data: const ArrowData(arrowType: ArrowType.elbow),
    startPosition: startPosition,
  );
  var creating = CreatingState(
    element: ElementState(
      id: 'draft-arrow',
      rect: start.rect,
      rotation: 0,
      opacity: 1,
      zIndex: 10,
      data: start.data,
    ),
    startPosition: startPosition,
    currentRect: start.rect,
    creationMode: start.creationMode,
  );

  final firstUpdate = strategy.update(
    state: state,
    config: DrawConfig.defaultConfig,
    creatingState: creating,
    currentPosition: midPosition,
    maintainAspectRatio: false,
    createFromCenter: false,
    snappingMode: SnappingMode.none,
  );
  creating = creating.copyWith(
    element: creating.element.copyWith(
      rect: firstUpdate.rect,
      data: firstUpdate.data,
    ),
    currentRect: firstUpdate.rect,
    creationMode: firstUpdate.creationMode,
  );
  final secondUpdate = strategy.update(
    state: state,
    config: DrawConfig.defaultConfig,
    creatingState: creating,
    currentPosition: endPosition,
    maintainAspectRatio: false,
    createFromCenter: false,
    snappingMode: SnappingMode.none,
  );
  creating = creating.copyWith(
    element: creating.element.copyWith(
      rect: secondUpdate.rect,
      data: secondUpdate.data,
    ),
    currentRect: secondUpdate.rect,
    creationMode: secondUpdate.creationMode,
  );
  final finished = strategy.finish(
    state: state,
    config: DrawConfig.defaultConfig,
    creatingState: creating,
  );
  if (!finished.shouldCommit) {
    throw StateError('expected elbow creation to commit');
  }
  return ElementState(
    id: 'created-elbow',
    rect: finished.rect,
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: finished.data,
  );
}
