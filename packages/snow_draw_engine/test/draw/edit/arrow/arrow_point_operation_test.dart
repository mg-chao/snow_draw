import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/edit_context.dart';
import 'package:snow_draw_engine/draw/types/edit_transform.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowPointOperation core endpoint drag integration', () {
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
        pointKind: ArrowPointKind.turning,
        pointIndex: 1,
        startPosition: const DrawPoint(x: 160, y: 60),
        currentPosition: const DrawPoint(x: 240, y: 60),
      );

      expect(session.transform.orderedElementIds, isNotNull);
      final next = const ArrowPointOperation().finish(
        state: state,
        context: session.context,
        transform: session.transform,
      );

      final orderedIds = next.domain.document.elements
          .map((element) => element.id)
          .toList(growable: false);
      expect(orderedIds, <String>[bindTarget.id, arrow.id]);
    });

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
      final overlay = ArrowPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: state.domain.document.elements,
      );
      final focusHandle = overlay.focusPoints.singleWhere(
        (handle) => handle.kind == ArrowPointKind.focusStart,
      );

      final session = _dragArrowHandleSession(
        state: state,
        elementId: arrow.id,
        pointKind: ArrowPointKind.focusStart,
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
}

ArrowPointTransform _dragArrowEndpoint({
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
    pointKind: ArrowPointKind.turning,
    pointIndex: endpointIndex,
    startPosition: startPosition,
    currentPosition: currentPosition,
    modifiers: modifiers,
  );
  return session.transform;
}

({EditContext context, ArrowPointTransform transform}) _dragArrowHandleSession({
  required DrawState state,
  required String elementId,
  required ArrowPointKind pointKind,
  required int pointIndex,
  required DrawPoint startPosition,
  required DrawPoint currentPosition,
  EditModifiers modifiers = const EditModifiers(),
}) {
  const operation = ArrowPointOperation();
  final context = operation.createContext(
    state: state,
    position: startPosition,
    params: ArrowPointOperationParams(
      elementId: elementId,
      pointKind: pointKind,
      pointIndex: pointIndex,
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
  return (context: context, transform: update.transform as ArrowPointTransform);
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
    data: ArrowData(
      points: normalized,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}
