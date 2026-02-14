import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/reducers/camera/camera_reducer.dart';
import 'package:snow_draw_core/draw/reducers/interaction/selection/pending_state_reducer.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('Reducer interaction scoping', () {
    test(
      'CancelBoxSelect does not cancel text editing when not box selecting',
      () async {
        final store = _createStore(initialState: _stateWithTextEditing());
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(const CancelBoxSelect());

        expect(store.state, same(before));
        expect(store.state.application.interaction, isA<TextEditingState>());
      },
    );

    test(
      'FinishBoxSelect does not cancel creating when not box selecting',
      () async {
        final store = _createStore(initialState: _stateWithCreating());
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(const FinishBoxSelect());

        expect(store.state, same(before));
        expect(store.state.application.interaction, isA<CreatingState>());
      },
    );

    test(
      'CancelCreateElement does not cancel text editing when not creating',
      () async {
        final store = _createStore(initialState: _stateWithTextEditing());
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(const CancelCreateElement());

        expect(store.state, same(before));
        expect(store.state.application.interaction, isA<TextEditingState>());
      },
    );

    test(
      'FinishCreateElement does not cancel box selecting when not creating',
      () async {
        final store = _createStore(initialState: _stateWithBoxSelecting());
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(const FinishCreateElement());

        expect(store.state, same(before));
        expect(store.state.application.interaction, isA<BoxSelectingState>());
      },
    );
  });

  group('Reducer no-op allocations', () {
    test(
      'cameraReducer returns original state when MoveCamera delta is zero',
      () {
        final state = DrawState();

        final next = cameraReducer(
          state,
          const MoveCamera(dx: 0, dy: 0),
          const _NoopCameraReducerDeps(),
        );

        expect(next, same(state));
      },
    );

    test('PendingStateReducer returns original state for identical '
        'drag pending payload', () {
      const pointerDown = DrawPoint(x: 20, y: 30);
      final base = DrawState();
      final pendingState = base.copyWith(
        application: base.application.copyWith(
          interaction: const DragPendingState(
            pointerDownPosition: pointerDown,
            intent: PendingMoveIntent(),
          ),
        ),
      );

      const reducer = PendingStateReducer();
      final next = reducer.reduce(
        pendingState,
        const SetDragPending(
          pointerDownPosition: pointerDown,
          intent: PendingMoveIntent(),
        ),
      );

      expect(next, same(pendingState));
    });
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithTextEditing() {
  const elementId = 'text-1';
  const rect = DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 50);

  final state = DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: const [
          ElementState(
            id: elementId,
            rect: rect,
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: TextData(text: 'hello'),
          ),
        ],
      ),
      selection: const SelectionState(selectedIds: {elementId}),
    ),
  );

  return state.copyWith(
    application: state.application.copyWith(
      interaction: const TextEditingState(
        elementId: elementId,
        draftData: TextData(text: 'hello'),
        rect: rect,
        isNew: false,
        opacity: 1,
        rotation: 0,
      ),
    ),
  );
}

DrawState _stateWithCreating() {
  const rect = DrawRect(maxX: 16, maxY: 16);
  final state = DrawState();

  return state.copyWith(
    application: state.application.copyWith(
      interaction: CreatingState(
        element: const ElementState(
          id: 'creating-1',
          rect: rect,
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        startPosition: DrawPoint.zero,
        currentRect: rect,
      ),
    ),
  );
}

DrawState _stateWithBoxSelecting() {
  final state = DrawState();
  return state.copyWith(
    application: state.application.copyWith(
      interaction: const BoxSelectingState(
        startPosition: DrawPoint(x: 5, y: 5),
        currentPosition: DrawPoint(x: 25, y: 25),
      ),
    ),
  );
}

class _NoopCameraReducerDeps implements CameraReducerDeps {
  const _NoopCameraReducerDeps();
}
