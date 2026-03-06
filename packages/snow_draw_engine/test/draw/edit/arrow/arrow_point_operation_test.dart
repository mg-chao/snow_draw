import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/connector/connector_point_operation.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_points.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_routing_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/edit_context.dart';
import 'package:snow_draw_engine/draw/types/edit_transform.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:snow_draw_engine/draw/utils/combined_element_lookup.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectorPointOperation core endpoint drag integration', () {
    test('dragging endpoint without movement is treated as no-op', () {
      final arrow = _arrowElement(
        id: 'arrow-noop',
        points: const <DrawPoint>[
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 160, y: 60),
        ],
        zIndex: 1,
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );

      final transform = _dragArrowEndpoint(
        state: state,
        elementId: arrow.id,
        endpointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 160, y: 60),
      );

      expect(transform.hasChanges, isFalse);
      expect(transform.orderedElementIds, isNull);
      expect(transform.endBinding, isNull);
    });

    test('dragging endpoint near bindable creates binding via core engine', () {
      final bindTarget = _rectangleElement(
        id: 'rect-target',
        rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
        zIndex: 1,
      );
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 160, y: 60),
        ],
        zIndex: 2,
      );
      final state = _stateWithElements(
        <ElementState>[bindTarget, arrow],
        selectedIds: <String>{arrow.id},
      );

      final transform = _dragArrowEndpoint(
        state: state,
        elementId: arrow.id,
        endpointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 240, y: 60),
      );

      expect(transform.hasChanges, isTrue);
      expect(transform.endBinding, isNotNull);
      expect(transform.endBinding!.elementId, bindTarget.id);
      expect(transform.points.last.x, greaterThan(160));
    });

    test('dragging endpoint with fromCenter requests inside binding mode', () {
      final bindTarget = _rectangleElement(
        id: 'rect-target',
        rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
        zIndex: 1,
      );
      final arrow = _arrowElement(
        id: 'arrow-inside',
        points: const <DrawPoint>[
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 160, y: 60),
        ],
        zIndex: 2,
      );
      final state = _stateWithElements(
        <ElementState>[bindTarget, arrow],
        selectedIds: <String>{arrow.id},
      );

      final transform = _dragArrowEndpoint(
        state: state,
        elementId: arrow.id,
        endpointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 240, y: 60),
        modifiers: const EditModifiers(fromCenter: true),
      );

      expect(transform.hasChanges, isTrue);
      expect(transform.endBinding, isNotNull);
      expect(transform.endBinding!.elementId, bindTarget.id);
      expect(transform.endBinding!.mode, ArrowBindingMode.inside);
    });

    test(
      'snap override prevents rebinding endpoint to a different element',
      () {
        final initialTarget = _rectangleElement(
          id: 'rect-initial',
          rect: const DrawRect(minX: 180, maxX: 260, maxY: 120),
          zIndex: 1,
        );
        final nextTarget = _rectangleElement(
          id: 'rect-next',
          rect: const DrawRect(minX: 340, maxX: 440, maxY: 120),
          zIndex: 2,
        );
        final arrow = _arrowElement(
          id: 'arrow-2',
          points: const <DrawPoint>[
            DrawPoint(x: 80, y: 60),
            DrawPoint(x: 220, y: 60),
          ],
          zIndex: 3,
          endBinding: const ArrowBinding(
            elementId: 'rect-initial',
            anchor: DrawPoint(x: 0, y: 0.5),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[initialTarget, nextTarget, arrow],
          selectedIds: <String>{arrow.id},
        );

        final transform = _dragArrowEndpoint(
          state: state,
          elementId: arrow.id,
          endpointIndex: 1,
          startPosition: const DrawPoint(x: 220, y: 60),
          currentPosition: const DrawPoint(x: 360, y: 60),
          modifiers: const EditModifiers(snapOverride: true),
        );

        expect(transform.hasChanges, isTrue);
        expect(transform.endBinding, isNull);
      },
    );

    test('finish keeps endpoint unbound when snap override is active', () {
      final initialTarget = _rectangleElement(
        id: 'rect-initial-finish',
        rect: const DrawRect(minX: 180, maxX: 260, maxY: 120),
        zIndex: 1,
      );
      final nextTarget = _rectangleElement(
        id: 'rect-next-finish',
        rect: const DrawRect(minX: 340, maxX: 440, maxY: 120),
        zIndex: 2,
      );
      final arrow = _arrowElement(
        id: 'arrow-snap-finish',
        points: const <DrawPoint>[
          DrawPoint(x: 80, y: 60),
          DrawPoint(x: 220, y: 60),
        ],
        zIndex: 3,
        endBinding: const ArrowBinding(
          elementId: 'rect-initial-finish',
          anchor: DrawPoint(x: 0, y: 0.5),
        ),
      );
      final state = _stateWithElements(
        <ElementState>[initialTarget, nextTarget, arrow],
        selectedIds: <String>{arrow.id},
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 220, y: 60),
        currentPosition: const DrawPoint(x: 360, y: 60),
        modifiers: const EditModifiers(snapOverride: true),
      );
      final next = const ConnectorPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );
      final updatedArrow = next.domain.document.getElementById(arrow.id)!;
      final updatedData = updatedArrow.data as ArrowData;

      expect(updatedData.endBinding, isNull);
    });

    test('snap override prevents reorder fallback while dragging endpoint', () {
      final bindTarget = _rectangleElement(
        id: 'rect-snap-reorder',
        rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
        zIndex: 1,
      );
      final arrow = _arrowElement(
        id: 'arrow-snap-reorder',
        points: const <DrawPoint>[
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 160, y: 60),
        ],
        zIndex: 0,
      );
      final state = _stateWithElements(
        <ElementState>[arrow, bindTarget],
        selectedIds: <String>{arrow.id},
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 240, y: 60),
        modifiers: const EditModifiers(snapOverride: true),
      );

      expect(session.transform.endBinding, isNull);
      expect(session.transform.orderedElementIds, isNull);

      final next = const ConnectorPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );
      final orderedIds = next.domain.document.elements
          .map((element) => element.id)
          .toList(growable: false);
      expect(orderedIds, <String>[arrow.id, bindTarget.id]);
    });

    test(
      'finish finalizes endpoint drag with core default same-target behavior',
      () {
        final bindTarget = _rectangleElement(
          id: 'rect-shared',
          rect: const DrawRect(maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-shared',
          points: const <DrawPoint>[
            DrawPoint(x: 100, y: 60),
            DrawPoint(x: 80, y: 60),
          ],
          zIndex: 2,
          startBinding: const ArrowBinding(
            elementId: 'rect-shared',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
          endBinding: const ArrowBinding(
            elementId: 'rect-shared',
            anchor: DrawPoint(x: 0.8, y: 0.5),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[bindTarget, arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: 0,
          startPosition: const DrawPoint(x: 100, y: 60),
          currentPosition: const DrawPoint(x: 92, y: 60),
        );

        expect(session.transform.startBinding, isNotNull);
        expect(session.transform.endBinding, isNotNull);

        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );
        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;

        expect(updatedData.startBinding, isNotNull);
        expect(updatedData.startBinding!.elementId, bindTarget.id);
        expect(updatedData.startBinding!.mode, ArrowBindingMode.inside);
        expect(updatedData.endBinding, isNotNull);
        expect(updatedData.endBinding!.elementId, bindTarget.id);
        expect(updatedData.endBinding!.mode, ArrowBindingMode.inside);
      },
    );

    test('finish applies reorder event and moves bound arrow above target', () {
      final bindTarget = _rectangleElement(
        id: 'rect-reorder',
        rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
        zIndex: 1,
      );
      final arrow = _arrowElement(
        id: 'arrow-reorder',
        points: const <DrawPoint>[
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 160, y: 60),
        ],
        zIndex: 0,
      );
      final state = _stateWithElements(
        <ElementState>[arrow, bindTarget],
        selectedIds: <String>{arrow.id},
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 240, y: 60),
      );

      expect(session.transform.orderedElementIds, isNotNull);
      final next = const ConnectorPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );

      final orderedIds = next.domain.document.elements
          .map((element) => element.id)
          .toList(growable: false);
      expect(orderedIds, <String>[bindTarget.id, arrow.id]);
    });

    test(
      'dragging already-bound endpoint can reorder using suggested bindable',
      () {
        final bindTarget = _rectangleElement(
          id: 'rect-suggested',
          rect: const DrawRect(maxX: 100, maxY: 100),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-suggested',
          points: const <DrawPoint>[
            DrawPoint(x: -120, y: 50),
            DrawPoint(x: 0, y: 50),
          ],
          zIndex: 0,
          endBinding: const ArrowBinding(
            elementId: 'rect-suggested',
            anchor: DrawPoint(x: 0, y: 0.5),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[arrow, bindTarget],
          selectedIds: <String>{arrow.id},
        );

        final transform = _dragArrowEndpoint(
          state: state,
          elementId: arrow.id,
          endpointIndex: 1,
          startPosition: const DrawPoint(x: 0, y: 50),
          currentPosition: const DrawPoint(x: 0, y: 50),
        );

        expect(transform.hasChanges, isTrue);
        expect(transform.orderedElementIds, <String>[bindTarget.id, arrow.id]);
      },
    );

    test('dragging focus handle routes through core focus drag '
        'and can switch to inside', () {
      final bindTarget = _rectangleElement(
        id: 'rect-focus-target',
        rect: const DrawRect(maxX: 100, maxY: 100),
        zIndex: 1,
      );
      const arrow = ElementState(
        id: 'arrow-focus-1',
        rect: DrawRect(minX: 120, minY: 20, maxX: 320, maxY: 21),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: ArrowData(
          points: <DrawPoint>[DrawPoint(x: 0, y: 0.5), DrawPoint(x: 1, y: 0.5)],
          startBinding: ArrowBinding(
            elementId: 'rect-focus-target',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        ),
      );
      final state = _stateWithElements(
        <ElementState>[bindTarget, arrow],
        selectedIds: <String>{arrow.id},
      );
      final overlay = ConnectorPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: state.domain.document.elements,
      );
      final focusHandle = overlay.focusPoints.singleWhere(
        (handle) => handle.kind == ConnectorPointKind.focusStart,
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.focusStart,
        pointIndex: focusHandle.index,
        startPosition: focusHandle.position,
        currentPosition: const DrawPoint(x: 40, y: 40),
        modifiers: const EditModifiers(fromCenter: true),
      );

      expect(session.transform.hasChanges, isTrue);
      expect(session.transform.startBinding, isNotNull);
      expect(session.transform.startBinding!.mode, ArrowBindingMode.inside);
    });
  });

  group('ConnectorPointOperation elbow parity', () {
    test('dragging addable midpoint creates and releases fixed segment', () {
      final arrow = _elbowArrowElement(
        id: 'elbow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 125, y: 0),
          DrawPoint(x: 125, y: 200),
          DrawPoint(x: 250, y: 200),
        ],
        zIndex: 1,
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );

      final dragged = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.addable,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 125, y: 100),
        currentPosition: const DrawPoint(x: 130, y: 100),
      );
      final draggedState = const ConnectorPointOperation().finish(
        state: state,
        context: dragged.context,
        transform: dragged.transform,
      );

      final draggedArrow = draggedState.domain.document.getElementById(
        arrow.id,
      )!;
      final draggedData = draggedArrow.data as ArrowData;
      final draggedPoints = ConnectorGeometry.resolveWorldPoints(
        rect: draggedArrow.rect,
        normalizedPoints: draggedData.points,
      );
      expect(draggedPoints, const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 130, y: 0),
        DrawPoint(x: 130, y: 200),
        DrawPoint(x: 250, y: 200),
      ]);
      expect(draggedData.fixedSegments, isNotNull);
      expect(draggedData.fixedSegments, hasLength(1));
      expect(draggedData.fixedSegments!.first.index, 2);

      final releaseState = _stateWithElements(
        <ElementState>[draggedArrow],
        selectedIds: <String>{draggedArrow.id},
      );
      final released = _dragArrowHandleSession(
        state: releaseState,
        elementId: draggedArrow.id,
        pointKind: ConnectorPointKind.addable,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 130, y: 100),
        currentPosition: const DrawPoint(x: 130, y: 100),
        isDoubleClick: true,
      );
      final releasedState = const ConnectorPointOperation().finish(
        state: releaseState,
        context: released.context,
        transform: released.transform,
      );
      final releasedArrow = releasedState.domain.document.getElementById(
        draggedArrow.id,
      )!;
      final releasedData = releasedArrow.data as ArrowData;
      final releasedPoints = ConnectorGeometry.resolveWorldPoints(
        rect: releasedArrow.rect,
        normalizedPoints: releasedData.points,
      );
      expect(releasedPoints, const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 125, y: 0),
        DrawPoint(x: 125, y: 200),
        DrawPoint(x: 250, y: 200),
      ]);
      expect(
        releasedData.fixedSegments == null ||
            releasedData.fixedSegments!.isEmpty,
        isTrue,
      );
    });

    test(
      'dragging start-adjacent fixed segment inserts a free segment at start',
      () {
        final arrow = _elbowArrowElement(
          id: 'elbow-start-segment',
          points: const <DrawPoint>[
            DrawPoint(x: 0, y: 0),
            DrawPoint(x: 125, y: 0),
            DrawPoint(x: 125, y: 200),
            DrawPoint(x: 250, y: 200),
          ],
          zIndex: 1,
        );
        final state = _stateWithElements(
          <ElementState>[arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.addable,
          pointIndex: 0,
          startPosition: const DrawPoint(x: 62.5, y: 0),
          currentPosition: const DrawPoint(x: 62.5, y: 20),
        );
        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );

        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;
        final updatedPoints = ConnectorGeometry.resolveWorldPoints(
          rect: updatedArrow.rect,
          normalizedPoints: updatedData.points,
        );

        expect(updatedPoints, hasLength(5));
        expect(updatedPoints[0].x, closeTo(0, 1e-6));
        expect(updatedPoints[0].y, closeTo(0, 1e-6));
        expect(updatedPoints[1].x, closeTo(0, 1e-6));
        expect(updatedPoints[1].y, closeTo(20, 1e-6));
        expect(updatedPoints[2].x, closeTo(125, 1e-6));
        expect(updatedPoints[2].y, closeTo(20, 1e-6));
        expect(updatedPoints[3].x, closeTo(125, 1e-6));
        expect(updatedPoints[3].y, closeTo(200, 1e-6));
        expect(updatedPoints[4].x, closeTo(250, 1e-6));
        expect(updatedPoints[4].y, closeTo(200, 1e-6));

        expect(updatedData.fixedSegments, isNotNull);
        expect(updatedData.fixedSegments, hasLength(1));
        expect(updatedData.fixedSegments!.first.index, 2);
        expect(updatedData.fixedSegments!.first.start.x, closeTo(0, 1e-6));
        expect(updatedData.fixedSegments!.first.start.y, closeTo(20, 1e-6));
        expect(updatedData.fixedSegments!.first.end.x, closeTo(125, 1e-6));
        expect(updatedData.fixedSegments!.first.end.y, closeTo(20, 1e-6));
      },
    );

    test('dragging elbow endpoint preserves existing fixed segment lock', () {
      final arrow = _elbowArrowElement(
        id: 'elbow-endpoint',
        points: const <DrawPoint>[
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 130, y: 0),
          DrawPoint(x: 130, y: 200),
          DrawPoint(x: 250, y: 200),
        ],
        zIndex: 1,
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 2,
            start: DrawPoint(x: 130, y: 0),
            end: DrawPoint(x: 130, y: 200),
          ),
        ],
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 3,
        startPosition: const DrawPoint(x: 250, y: 200),
        currentPosition: const DrawPoint(x: 270, y: 200),
      );
      final next = const ConnectorPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );
      final updatedArrow = next.domain.document.getElementById(arrow.id)!;
      final updatedData = updatedArrow.data as ArrowData;
      final updatedPoints = ConnectorGeometry.resolveWorldPoints(
        rect: updatedArrow.rect,
        normalizedPoints: updatedData.points,
      );
      expect(updatedPoints.first, const DrawPoint(x: 0, y: 0));
      expect(updatedPoints.last, const DrawPoint(x: 270, y: 200));
      expect(updatedData.fixedSegments, isNotNull);
      expect(updatedData.fixedSegments, hasLength(1));
      expect(updatedData.fixedSegments!.first.index, 2);
      expect(updatedData.fixedSegments!.first.start.x, closeTo(130, 1e-6));
      expect(updatedData.fixedSegments!.first.end.x, closeTo(130, 1e-6));
    });

    test(
      'dragging bound elbow endpoint along same bindable edge updates anchor',
      () {
        final bindTarget = _rectangleElement(
          id: 'elbow-bind-target',
          rect: const DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200),
          zIndex: 1,
        );
        final arrow = _elbowArrowElement(
          id: 'elbow-bound-slide',
          points: const <DrawPoint>[
            DrawPoint(x: 100, y: 150),
            DrawPoint(x: 300, y: 150),
          ],
          zIndex: 2,
          startBinding: const ArrowBinding(
            elementId: 'elbow-bind-target',
            anchor: DrawPoint(x: 0, y: 0.5),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[bindTarget, arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: 0,
          startPosition: const DrawPoint(x: 100, y: 150),
          currentPosition: const DrawPoint(x: 100, y: 190),
        );
        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );
        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;
        final updatedPoints = ConnectorGeometry.resolveWorldPoints(
          rect: updatedArrow.rect,
          normalizedPoints: updatedData.points,
        );

        expect(updatedData.startBinding, isNotNull);
        expect(updatedData.startBinding!.elementId, bindTarget.id);
        expect(updatedData.startBinding!.anchor.y, greaterThan(0.7));
        expect(updatedPoints.first.y, greaterThan(180));
      },
    );

    test('dragging elbow endpoint with alt keeps orbit binding mode', () {
      final bindTarget = _rectangleElement(
        id: 'elbow-alt-target',
        rect: const DrawRect(minX: 300, minY: 120, maxX: 420, maxY: 260),
        zIndex: 1,
      );
      final arrow = _elbowArrowElement(
        id: 'elbow-alt-mode',
        points: const <DrawPoint>[
          DrawPoint(x: 120, y: 180),
          DrawPoint(x: 220, y: 180),
        ],
        zIndex: 2,
      );
      final state = _stateWithElements(
        <ElementState>[bindTarget, arrow],
        selectedIds: <String>{arrow.id},
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 220, y: 180),
        currentPosition: const DrawPoint(x: 320, y: 180),
        modifiers: const EditModifiers(fromCenter: true),
      );
      final next = const ConnectorPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );
      final updatedArrow = next.domain.document.getElementById(arrow.id)!;
      final updatedData = updatedArrow.data as ArrowData;

      expect(updatedData.endBinding, isNotNull);
      expect(updatedData.endBinding!.elementId, bindTarget.id);
      expect(updatedData.endBinding!.mode, ArrowBindingMode.orbit);
    });

    test(
      'snap override clears dragged elbow endpoint binding even over same target',
      () {
        final bindTarget = _rectangleElement(
          id: 'elbow-snap-target',
          rect: const DrawRect(minX: 300, minY: 120, maxX: 420, maxY: 260),
          zIndex: 1,
        );
        final arrow = _elbowArrowElement(
          id: 'elbow-snap-override',
          points: const <DrawPoint>[
            DrawPoint(x: 120, y: 180),
            DrawPoint(x: 300, y: 180),
          ],
          zIndex: 2,
          endBinding: const ArrowBinding(
            elementId: 'elbow-snap-target',
            anchor: DrawPoint(x: 0, y: 0.5),
            mode: ArrowBindingMode.orbit,
          ),
        );
        final state = _stateWithElements(
          <ElementState>[bindTarget, arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: 1,
          startPosition: const DrawPoint(x: 300, y: 180),
          currentPosition: const DrawPoint(x: 320, y: 180),
          modifiers: const EditModifiers(snapOverride: true),
        );

        expect(session.transform.endBinding, isNull);
        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );
        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;
        expect(updatedData.endBinding, isNull);
      },
    );

    test(
      'dragging elbow endpoint keeps connected segment routing consistent',
      () {
        final arrow = _elbowArrowElement(
          id: 'elbow-endpoint-connected-segment',
          points: const <DrawPoint>[
            DrawPoint(x: 0, y: 0),
            DrawPoint(x: 120, y: 0),
            DrawPoint(x: 120, y: 120),
            DrawPoint(x: 220, y: 120),
            DrawPoint(x: 220, y: 220),
          ],
          zIndex: 1,
          fixedSegments: const <ElbowFixedSegment>[
            ElbowFixedSegment(
              index: 2,
              start: DrawPoint(x: 120, y: 0),
              end: DrawPoint(x: 120, y: 120),
            ),
            ElbowFixedSegment(
              index: 4,
              start: DrawPoint(x: 220, y: 120),
              end: DrawPoint(x: 220, y: 220),
            ),
          ],
        );
        final state = _stateWithElements(
          <ElementState>[arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: 4,
          startPosition: const DrawPoint(x: 220, y: 220),
          currentPosition: const DrawPoint(x: 300, y: 260),
        );
        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );

        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;
        final updatedPoints = ConnectorGeometry.resolveWorldPoints(
          rect: updatedArrow.rect,
          normalizedPoints: updatedData.points,
        );

        expect(updatedPoints, hasLength(5));
        expect(updatedPoints[0].x, closeTo(0, 1e-6));
        expect(updatedPoints[0].y, closeTo(0, 1e-6));
        expect(updatedPoints[1].x, closeTo(120, 1e-6));
        expect(updatedPoints[1].y, closeTo(0, 1e-6));
        expect(updatedPoints[2].x, closeTo(120, 1e-6));
        expect(updatedPoints[2].y, closeTo(120, 1e-6));
        expect(updatedPoints[3].x, closeTo(300, 1e-6));
        expect(updatedPoints[3].y, closeTo(120, 1e-6));
        expect(updatedPoints[4].x, closeTo(300, 1e-6));
        expect(updatedPoints[4].y, closeTo(260, 1e-6));

        expect(updatedData.fixedSegments, isNotNull);
        expect(updatedData.fixedSegments, hasLength(2));
        expect(updatedData.fixedSegments![0].index, 2);
        expect(updatedData.fixedSegments![0].start.x, closeTo(120, 1e-6));
        expect(updatedData.fixedSegments![0].start.y, closeTo(0, 1e-6));
        expect(updatedData.fixedSegments![0].end.x, closeTo(120, 1e-6));
        expect(updatedData.fixedSegments![0].end.y, closeTo(120, 1e-6));
        expect(updatedData.fixedSegments![1].index, 4);
        expect(updatedData.fixedSegments![1].start.x, closeTo(300, 1e-6));
        expect(updatedData.fixedSegments![1].start.y, closeTo(120, 1e-6));
        expect(updatedData.fixedSegments![1].end.x, closeTo(300, 1e-6));
        expect(updatedData.fixedSegments![1].end.y, closeTo(260, 1e-6));
      },
    );

    test('elbow endpoint preview writes back from endpoints only', () {
      final arrow = _elbowArrowElement(
        id: 'elbow-endpoint-preview-endpoints-only',
        points: const <DrawPoint>[
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 20, y: 0),
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 40, y: 20),
          DrawPoint(x: 40, y: 40),
          DrawPoint(x: 60, y: 40),
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 80, y: 60),
        ],
        zIndex: 1,
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 2,
            start: DrawPoint(x: 20, y: 0),
            end: DrawPoint(x: 20, y: 20),
          ),
          ElbowFixedSegment(
            index: 4,
            start: DrawPoint(x: 40, y: 20),
            end: DrawPoint(x: 40, y: 40),
          ),
        ],
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );
      final data = arrow.data as ArrowData;
      const previewPoints = <DrawPoint>[
        DrawPoint(x: 0, y: 10),
        DrawPoint(x: 20, y: 0),
        DrawPoint(x: 20, y: 20),
        DrawPoint(x: 40, y: 20),
        DrawPoint(x: 40, y: 40),
        DrawPoint(x: 60, y: 40),
        DrawPoint(x: 60, y: 60),
        DrawPoint(x: 80, y: 60),
        DrawPoint(x: 80, y: 90),
      ];
      final context = ConnectorPointEditContext(
        startPosition: const DrawPoint(x: 80, y: 60),
        startBounds: arrow.rect,
        selectedIdsAtStart: <String>{arrow.id},
        selectionVersion: state.domain.selection.selectionVersion,
        elementsVersion: state.domain.document.elementsVersion,
        elementId: arrow.id,
        elementRect: arrow.rect,
        rotation: arrow.rotation,
        initialPoints: ConnectorGeometry.resolveWorldPoints(
          rect: arrow.rect,
          normalizedPoints: data.points,
        ),
        initialFixedSegments: data.fixedSegments ?? const <ElbowFixedSegment>[],
        arrowType: ArrowType.elbow,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 7,
        dragOffset: const DrawPoint(x: 0, y: 0),
        baseElement: arrow,
        elementSpace: null,
        releaseFixedSegment: false,
        deletePointOnStart: false,
        startArrowhead: data.startArrowhead,
        endArrowhead: data.endArrowhead,
        initialStartBinding: data.startBinding,
        initialEndBinding: data.endBinding,
        hasBindableTargets: false,
      );
      final transform = ConnectorPointTransform(
        currentPosition: previewPoints.last,
        points: previewPoints,
        fixedSegments: data.fixedSegments,
        startBinding: data.startBinding,
        endBinding: data.endBinding,
        activeIndex: previewPoints.length - 1,
        hasChanges: true,
      );

      final result = const ConnectorPointOperation().computeResult(
        state: state,
        context: context,
        transform: transform,
      );

      expect(result, isNotNull);
      final updatedArrow = result!.updatedElements[arrow.id]!;
      final updatedData = updatedArrow.data as ArrowData;
      final updatedPoints = ConnectorGeometry.resolveWorldPoints(
        rect: updatedArrow.rect,
        normalizedPoints: updatedData.points,
      );
      final expected = computeElbowEdit(
        element: arrow,
        data: data,
        lookup: CombinedElementLookup(base: state.domain.document.elementMap),
        localPointsOverride: <DrawPoint>[
          previewPoints.first,
          previewPoints.last,
        ],
      );

      expect(updatedPoints, expected.localPoints);
      expect(updatedPoints, hasLength(8));
      expect(updatedData.fixedSegments, expected.fixedSegments);
    });

    test('finishing elbow endpoint drag tolerates expanded preview points', () {
      final arrow = _elbowArrowElement(
        id: 'elbow-endpoint-finish-expanded-preview',
        points: const <DrawPoint>[
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 20, y: 0),
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 40, y: 20),
          DrawPoint(x: 40, y: 40),
          DrawPoint(x: 60, y: 40),
          DrawPoint(x: 60, y: 60),
          DrawPoint(x: 80, y: 60),
        ],
        zIndex: 1,
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 2,
            start: DrawPoint(x: 20, y: 0),
            end: DrawPoint(x: 20, y: 20),
          ),
          ElbowFixedSegment(
            index: 4,
            start: DrawPoint(x: 40, y: 20),
            end: DrawPoint(x: 40, y: 40),
          ),
        ],
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );
      final data = arrow.data as ArrowData;
      const previewPoints = <DrawPoint>[
        DrawPoint(x: 0, y: 10),
        DrawPoint(x: 20, y: 0),
        DrawPoint(x: 20, y: 20),
        DrawPoint(x: 40, y: 20),
        DrawPoint(x: 40, y: 40),
        DrawPoint(x: 60, y: 40),
        DrawPoint(x: 60, y: 60),
        DrawPoint(x: 80, y: 60),
        DrawPoint(x: 80, y: 90),
      ];
      final context = ConnectorPointEditContext(
        startPosition: const DrawPoint(x: 80, y: 60),
        startBounds: arrow.rect,
        selectedIdsAtStart: <String>{arrow.id},
        selectionVersion: state.domain.selection.selectionVersion,
        elementsVersion: state.domain.document.elementsVersion,
        elementId: arrow.id,
        elementRect: arrow.rect,
        rotation: arrow.rotation,
        initialPoints: ConnectorGeometry.resolveWorldPoints(
          rect: arrow.rect,
          normalizedPoints: data.points,
        ),
        initialFixedSegments: data.fixedSegments ?? const <ElbowFixedSegment>[],
        arrowType: ArrowType.elbow,
        pointKind: ConnectorPointKind.turning,
        pointIndex: 7,
        dragOffset: const DrawPoint(x: 0, y: 0),
        baseElement: arrow,
        elementSpace: null,
        releaseFixedSegment: false,
        deletePointOnStart: false,
        startArrowhead: data.startArrowhead,
        endArrowhead: data.endArrowhead,
        initialStartBinding: data.startBinding,
        initialEndBinding: data.endBinding,
        hasBindableTargets: false,
      );
      final transform = ConnectorPointTransform(
        currentPosition: previewPoints.last,
        points: previewPoints,
        fixedSegments: data.fixedSegments,
        startBinding: data.startBinding,
        endBinding: data.endBinding,
        activeIndex: previewPoints.length - 1,
        hasChanges: true,
      );

      final next = const ConnectorPointOperation().finish(
        state: state,
        context: context,
        transform: transform,
      );
      final updatedArrow = next.domain.document.getElementById(arrow.id)!;
      final updatedData = updatedArrow.data as ArrowData;
      final updatedPoints = ConnectorGeometry.resolveWorldPoints(
        rect: updatedArrow.rect,
        normalizedPoints: updatedData.points,
      );

      expect(updatedPoints, hasLength(8));
      expect(updatedPoints.first, const DrawPoint(x: 0, y: 10));
      expect(updatedPoints.last, const DrawPoint(x: 80, y: 90));
      expect(updatedData.fixedSegments, hasLength(2));
    });

    test(
      'dragging elbow end endpoint keeps existing start binding element',
      () {
        final startTarget = _rectangleElement(
          id: 'elbow-start-target',
          rect: const DrawRect(minX: 40, minY: 40, maxX: 140, maxY: 140),
          zIndex: 1,
        );
        final endTarget = _rectangleElement(
          id: 'elbow-end-target',
          rect: const DrawRect(minX: 320, minY: 40, maxX: 420, maxY: 140),
          zIndex: 2,
        );
        final arrow = _elbowArrowElement(
          id: 'elbow-bound-end-drag',
          points: const <DrawPoint>[
            DrawPoint(x: 130, y: 60),
            DrawPoint(x: 260, y: 90),
          ],
          zIndex: 3,
          startBinding: const ArrowBinding(
            elementId: 'elbow-start-target',
            anchor: DrawPoint(x: 0.9, y: 0.2),
          ),
        );
        final state = _stateWithElements(
          <ElementState>[startTarget, endTarget, arrow],
          selectedIds: <String>{arrow.id},
        );

        final session = _dragArrowHandleSession(
          state: state,
          elementId: arrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: 1,
          startPosition: const DrawPoint(x: 260, y: 90),
          currentPosition: const DrawPoint(x: 330, y: 90),
        );
        final next = const ConnectorPointOperation().finish(
          state: state,
          context: session.context,
          transform: session.transform,
        );
        final updatedArrow = next.domain.document.getElementById(arrow.id)!;
        final updatedData = updatedArrow.data as ArrowData;

        expect(updatedData.startBinding, isNotNull);
        expect(updatedData.startBinding!.elementId, startTarget.id);
        expect(updatedData.startBinding!.anchor.x, closeTo(0.9, 1e-6));
        expect(updatedData.startBinding!.anchor.y, closeTo(0.2, 1e-6));
        expect(updatedData.endBinding, isNotNull);
        expect(updatedData.endBinding!.elementId, endTarget.id);
      },
    );

    test(
      'rebinding endpoint after dual-bound elbow creation avoids zig-zag route',
      () {
        final startTarget = _rectangleElement(
          id: 'rebind-start-target',
          rect: const DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 220),
          zIndex: 1,
        );
        final currentEndTarget = _rectangleElement(
          id: 'rebind-current-end-target',
          rect: const DrawRect(minX: 420, minY: 120, maxX: 560, maxY: 260),
          zIndex: 2,
        );
        final nextEndTarget = _rectangleElement(
          id: 'rebind-next-end-target',
          rect: const DrawRect(minX: 700, minY: 80, maxX: 860, maxY: 240),
          zIndex: 3,
        );
        final creationState = _stateWithElements(<ElementState>[
          startTarget,
          currentEndTarget,
          nextEndTarget,
        ]);
        final createdArrow = _createElbowArrowViaCreation(
          state: creationState,
          id: 'elbow-created-rebind',
          startPosition: const DrawPoint(x: 240, y: 160),
          midPosition: const DrawPoint(x: 320, y: 160),
          endPosition: const DrawPoint(x: 420, y: 190),
          zIndex: 4,
        );
        final createdData = createdArrow.data as ArrowData;
        final createdPoints = ConnectorGeometry.resolveWorldPoints(
          rect: createdArrow.rect,
          normalizedPoints: createdData.points,
        );
        final rebindingState = _stateWithElements(
          <ElementState>[
            startTarget,
            currentEndTarget,
            nextEndTarget,
            createdArrow,
          ],
          selectedIds: <String>{createdArrow.id},
        );

        final session = _dragArrowHandleSession(
          state: rebindingState,
          elementId: createdArrow.id,
          pointKind: ConnectorPointKind.turning,
          pointIndex: createdPoints.length - 1,
          startPosition: createdPoints.last,
          currentPosition: const DrawPoint(x: 700, y: 160),
        );
        final next = const ConnectorPointOperation().finish(
          state: rebindingState,
          context: session.context,
          transform: session.transform,
        );
        final updatedArrow = next.domain.document.getElementById(
          createdArrow.id,
        )!;
        final updatedData = updatedArrow.data as ArrowData;
        final updatedPoints = ConnectorGeometry.resolveWorldPoints(
          rect: updatedArrow.rect,
          normalizedPoints: updatedData.points,
        );

        expect(updatedData.startBinding, isNotNull);
        expect(updatedData.startBinding!.elementId, startTarget.id);
        expect(updatedData.endBinding, isNotNull);
        expect(updatedData.endBinding!.elementId, nextEndTarget.id);
        for (var index = 1; index < updatedPoints.length; index += 1) {
          final dx = (updatedPoints[index].x - updatedPoints[index - 1].x)
              .abs();
          final dy = (updatedPoints[index].y - updatedPoints[index - 1].y)
              .abs();
          expect(dx <= 1e-6 || dy <= 1e-6, isTrue);
        }
        for (var index = 2; index < updatedPoints.length; index += 1) {
          final prevDx =
              updatedPoints[index - 1].x - updatedPoints[index - 2].x;
          final prevDy =
              updatedPoints[index - 1].y - updatedPoints[index - 2].y;
          final nextDx = updatedPoints[index].x - updatedPoints[index - 1].x;
          final nextDy = updatedPoints[index].y - updatedPoints[index - 1].y;
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

ConnectorPointTransform _dragArrowEndpoint({
  required DrawState state,
  required String elementId,
  required int endpointIndex,
  required DrawPoint startPosition,
  required DrawPoint currentPosition,
  EditModifiers modifiers = const EditModifiers(),
}) {
  final session = _dragArrowHandleSession(
    state: state,
    elementId: elementId,
    pointKind: ConnectorPointKind.turning,
    pointIndex: endpointIndex,
    startPosition: startPosition,
    currentPosition: currentPosition,
    modifiers: modifiers,
  );
  return session.transform;
}

({EditContext context, ConnectorPointTransform transform})
_dragArrowHandleSession({
  required DrawState state,
  required String elementId,
  required ConnectorPointKind pointKind,
  required int pointIndex,
  required DrawPoint startPosition,
  required DrawPoint currentPosition,
  bool isDoubleClick = false,
  EditModifiers modifiers = const EditModifiers(),
}) {
  const operation = ConnectorPointOperation();
  final context = operation.createContext(
    state: state,
    position: startPosition,
    params: ConnectorPointOperationParams(
      elementId: elementId,
      pointKind: pointKind,
      pointIndex: pointIndex,
      isDoubleClick: isDoubleClick,
    ),
  );
  final initial = operation.initialTransform(
    state: state,
    context: context,
    startPosition: startPosition,
  );
  final update = operation.update(
    state: state,
    context: context,
    transform: initial,
    currentPosition: currentPosition,
    modifiers: modifiers,
    config: DrawConfig.defaultConfig,
  );
  return (
    context: context,
    transform: update.transform as ConnectorPointTransform,
  );
}

ElementState _elbowArrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  List<ElbowFixedSegment>? fixedSegments,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      arrowType: ArrowType.elbow,
      elbowRoutingData: fixedSegments == null
          ? null
          : ElbowRoutingData(fixedSegments: fixedSegments),
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}

DrawState _stateWithElements(
  List<ElementState> elements, {
  Set<String>? selectedIds,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds ?? const <String>{}),
  ),
);

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
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}

ElementState _createElbowArrowViaCreation({
  required DrawState state,
  required String id,
  required DrawPoint startPosition,
  required DrawPoint midPosition,
  required DrawPoint endPosition,
  required int zIndex,
}) {
  const strategy = ArrowCreationStrategy();
  final start = strategy.start(
    data: const ArrowData(arrowType: ArrowType.elbow),
    startPosition: startPosition,
  );
  var creating = CreatingState(
    element: ElementState(
      id: 'draft-$id',
      rect: start.rect,
      rotation: 0,
      opacity: 1,
      zIndex: zIndex,
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
  final finish = strategy.finish(
    state: state,
    config: DrawConfig.defaultConfig,
    creatingState: creating,
  );
  if (!finish.shouldCommit) {
    throw StateError('expected elbow creation to commit');
  }
  return ElementState(
    id: id,
    rect: finish.rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: finish.data,
  );
}
