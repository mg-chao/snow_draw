import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('History z-index behavior', () {
    test(
      'ChangeElementZIndex records full snapshots and keeps undo/redo zIndex stable',
      () async {
        final store = _createStore(initialState: _stateWithElements(4));
        addTearDown(store.dispose);

        await store.dispatch(
          const ChangeElementZIndex(
            elementId: 'a',
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = store.exportHistory().entries.last.delta;
        expect(delta.beforeElements, hasLength(4));
        expect(delta.afterElements, hasLength(4));
        expect(delta.reindexZIndices, isFalse);

        expect(_elementOrder(store), ['b', 'c', 'd', 'a']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);

        await store.dispatch(const Undo());
        expect(_elementOrder(store), ['a', 'b', 'c', 'd']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);

        await store.dispatch(const Redo());
        expect(_elementOrder(store), ['b', 'c', 'd', 'a']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);
      },
    );

    test(
      'ChangeElementsZIndex records full snapshots and keeps undo/redo zIndex stable',
      () async {
        final store = _createStore(initialState: _stateWithElements(4));
        addTearDown(store.dispose);

        await store.dispatch(
          ChangeElementsZIndex(
            elementIds: ['a', 'b'],
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = store.exportHistory().entries.last.delta;
        expect(delta.beforeElements, hasLength(4));
        expect(delta.afterElements, hasLength(4));
        expect(delta.reindexZIndices, isFalse);

        expect(_elementOrder(store), ['c', 'd', 'a', 'b']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);

        await store.dispatch(const Undo());
        expect(_elementOrder(store), ['a', 'b', 'c', 'd']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);

        await store.dispatch(const Redo());
        expect(_elementOrder(store), ['c', 'd', 'a', 'b']);
        expect(_elementZIndexes(store), [0, 1, 2, 3]);
      },
    );

    test(
      'DeleteElements keeps existing non-contiguous zIndex values on redo',
      () async {
        final store = _createStore(initialState: _stateWithElements(3));
        addTearDown(store.dispose);

        await store.dispatch(DeleteElements(elementIds: ['b']));
        expect(_elementOrder(store), ['a', 'c']);
        expect(_elementZIndexes(store), [0, 2]);

        final delta = store.exportHistory().entries.last.delta;
        expect(delta.reindexZIndices, isFalse);

        await store.dispatch(const Undo());
        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [0, 1, 2]);

        await store.dispatch(const Redo());
        expect(_elementOrder(store), ['a', 'c']);
        expect(_elementZIndexes(store), [0, 2]);
      },
    );

    test(
      'ChangeElementZIndex no-op with stale zIndex keeps undo/redo fidelity',
      () async {
        final store = _createStore(initialState: _stateWithStaleZIndexes());
        addTearDown(store.dispose);

        await store.dispatch(
          const ChangeElementZIndex(
            elementId: 'c',
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = store.exportHistory().entries.last.delta;
        expect(delta.beforeElements, hasLength(3));
        expect(delta.afterElements, hasLength(3));
        expect(delta.reindexZIndices, isFalse);

        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [0, 1, 2]);

        await store.dispatch(const Undo());
        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [2, 0, 1]);

        await store.dispatch(const Redo());
        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [0, 1, 2]);
      },
    );

    test(
      'ChangeElementsZIndex no-op with stale zIndex keeps undo/redo fidelity',
      () async {
        final store = _createStore(initialState: _stateWithStaleZIndexes());
        addTearDown(store.dispose);

        await store.dispatch(
          ChangeElementsZIndex(
            elementIds: ['b', 'c'],
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = store.exportHistory().entries.last.delta;
        expect(delta.beforeElements, hasLength(3));
        expect(delta.afterElements, hasLength(3));
        expect(delta.reindexZIndices, isFalse);

        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [0, 1, 2]);

        await store.dispatch(const Undo());
        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [2, 0, 1]);

        await store.dispatch(const Redo());
        expect(_elementOrder(store), ['a', 'b', 'c']);
        expect(_elementZIndexes(store), [0, 1, 2]);
      },
    );
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithElements(int count) {
  final elements = <ElementState>[];
  for (var index = 0; index < count; index++) {
    final id = String.fromCharCode('a'.codeUnitAt(0) + index);
    elements.add(
      ElementState(
        id: id,
        rect: DrawRect(minX: index * 20, maxX: index * 20 + 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: index,
        data: const FilterData(),
      ),
    );
  }

  return DrawState(
    domain: DomainState(document: DocumentState(elements: elements)),
  );
}

DrawState _stateWithStaleZIndexes() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: const [
        ElementState(
          id: 'a',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: FilterData(),
        ),
        ElementState(
          id: 'b',
          rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: FilterData(),
        ),
        ElementState(
          id: 'c',
          rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(),
        ),
      ],
    ),
  ),
);

List<String> _elementOrder(DefaultDrawStore store) =>
    store.state.domain.document.elements.map((element) => element.id).toList();

List<int> _elementZIndexes(DefaultDrawStore store) => store
    .state
    .domain
    .document
    .elements
    .map((element) => element.zIndex)
    .toList();
