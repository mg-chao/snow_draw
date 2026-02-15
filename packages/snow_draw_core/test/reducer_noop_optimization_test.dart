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
import 'package:snow_draw_core/draw/reducers/element/delete_element_handler.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('Reducer no-op behavior', () {
    test('DeleteElements with empty ids keeps state unchanged', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final before = _stateWithElements(const [
        ElementState(
          id: 'a',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: FilterData(),
        ),
      ]);

      final next = handleDeleteElements(
        before,
        DeleteElements(elementIds: const []),
        context,
      );

      expect(next, same(before));
    });

    test(
      'DeleteElements with unknown ids keeps document version unchanged',
      () async {
        final store = _createStore(
          initialState: _stateWithElements(const [
            ElementState(
              id: 'a',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: FilterData(),
            ),
          ]),
        );
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(DeleteElements(elementIds: const ['missing']));

        expect(store.state, same(before));
      },
    );

    test('ChangeElementZIndex no-op does not rebuild state', () async {
      final store = _createStore(
        initialState: _stateWithElements(const [
          ElementState(
            id: 'a',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: FilterData(),
          ),
          ElementState(
            id: 'b',
            rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: FilterData(),
          ),
        ]),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(
        const ChangeElementZIndex(
          elementId: 'b',
          operation: ZIndexOperation.bringToFront,
        ),
      );

      expect(store.state, same(before));
    });

    test('ChangeElementsZIndex no-op does not rebuild state', () async {
      final store = _createStore(
        initialState: _stateWithElements(const [
          ElementState(
            id: 'a',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: FilterData(),
          ),
          ElementState(
            id: 'b',
            rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: FilterData(),
          ),
          ElementState(
            id: 'c',
            rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 2,
            data: FilterData(),
          ),
        ]),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(
        ChangeElementsZIndex(
          elementIds: const ['b', 'c'],
          operation: ZIndexOperation.bringToFront,
        ),
      );

      expect(store.state, same(before));
    });
  });

  group('Reducer z-index correctness', () {
    test(
      'ChangeElementZIndex uses list order instead of stale zIndex',
      () async {
        final store = _createStore(
          initialState: _stateWithElements(const [
            ElementState(
              id: 'a',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
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
              zIndex: 0,
              data: FilterData(),
            ),
          ]),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const ChangeElementZIndex(
            elementId: 'c',
            operation: ZIndexOperation.sendBackward,
          ),
        );

        final elements = store.state.domain.document.elements;
        expect(elements.map((element) => element.id), ['a', 'c', 'b']);
        expect(elements.map((element) => element.zIndex), [0, 1, 2]);
      },
    );

    test('ChangeElementZIndex no-op reindexes stale zIndex values', () async {
      final store = _createStore(
        initialState: _stateWithElements(const [
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
        ]),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(
        const ChangeElementZIndex(
          elementId: 'c',
          operation: ZIndexOperation.bringToFront,
        ),
      );

      final elements = store.state.domain.document.elements;
      expect(store.state, isNot(same(before)));
      expect(elements.map((element) => element.id), ['a', 'b', 'c']);
      expect(elements.map((element) => element.zIndex), [0, 1, 2]);
    });

    test('ChangeElementsZIndex no-op reindexes stale zIndex values', () async {
      final store = _createStore(
        initialState: _stateWithElements(const [
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
        ]),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(
        ChangeElementsZIndex(
          elementIds: const ['b', 'c'],
          operation: ZIndexOperation.bringToFront,
        ),
      );

      final elements = store.state.domain.document.elements;
      expect(store.state, isNot(same(before)));
      expect(elements.map((element) => element.id), ['a', 'b', 'c']);
      expect(elements.map((element) => element.zIndex), [0, 1, 2]);
    });
  });
}

DrawState _stateWithElements(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}
