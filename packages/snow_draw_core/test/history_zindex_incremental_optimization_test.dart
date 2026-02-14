import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('History z-index incremental optimization', () {
    test(
      'ChangeElementZIndex stores compact deltas and keeps undo/redo zIndex stable',
      () async {
        final store = _createStore(initialState: _stateWithElements(4));
        addTearDown(store.dispose);

        await store.dispatch(
          const ChangeElementZIndex(
            elementId: 'a',
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = _latestHistoryDelta(store.exportHistoryJson());
        expect(_mapEntryCount(delta['beforeElements']), 1);
        expect(_mapEntryCount(delta['afterElements']), 1);
        expect(delta['reindexZIndices'], isTrue);

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
      'ChangeElementsZIndex uses compact deltas and keeps undo/redo zIndex stable',
      () async {
        final store = _createStore(initialState: _stateWithElements(4));
        addTearDown(store.dispose);

        await store.dispatch(
          ChangeElementsZIndex(
            elementIds: ['a', 'b'],
            operation: ZIndexOperation.bringToFront,
          ),
        );

        final delta = _latestHistoryDelta(store.exportHistoryJson());
        expect(_mapEntryCount(delta['beforeElements']), 2);
        expect(_mapEntryCount(delta['afterElements']), 2);
        expect(delta['reindexZIndices'], isTrue);

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

        final delta = _latestHistoryDelta(store.exportHistoryJson());
        expect(delta['reindexZIndices'], isNot(true));

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

        final delta = _latestHistoryDelta(store.exportHistoryJson());
        expect(_mapEntryCount(delta['beforeElements']), 3);
        expect(_mapEntryCount(delta['afterElements']), 3);
        expect(delta['reindexZIndices'], isNot(true));

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

        final delta = _latestHistoryDelta(store.exportHistoryJson());
        expect(_mapEntryCount(delta['beforeElements']), 3);
        expect(_mapEntryCount(delta['afterElements']), 3);
        expect(delta['reindexZIndices'], isNot(true));

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

Map<String, dynamic> _latestHistoryDelta(Map<String, dynamic> historyJson) {
  final nodes = historyJson['nodes'] as List<dynamic>? ?? const [];
  for (var index = nodes.length - 1; index >= 0; index--) {
    final node = nodes[index];
    if (node is! Map<String, dynamic>) {
      continue;
    }
    final delta = node['delta'];
    if (delta is Map<String, dynamic>) {
      return delta;
    }
  }
  return const {};
}

int _mapEntryCount(Object? value) {
  if (value is Map) {
    return value.length;
  }
  return 0;
}

List<String> _elementOrder(DefaultDrawStore store) =>
    store.state.domain.document.elements.map((element) => element.id).toList();

List<int> _elementZIndexes(DefaultDrawStore store) => store
    .state
    .domain
    .document
    .elements
    .map((element) => element.zIndex)
    .toList();
