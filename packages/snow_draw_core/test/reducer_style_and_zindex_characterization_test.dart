import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('UpdateElementsStyle characterization', () {
    test(
      'updates in-progress text draft when element does not exist in document',
      () async {
        const draftId = 'draft-text';
        final initialState = DrawState(
          domain: DomainState(
            document: DocumentState(elements: [_filterElement('base', 0)]),
          ),
          application: DrawState().application.copyWith(
            interaction: const TextEditingState(
              elementId: draftId,
              draftData: TextData(text: 'draft', fontSize: 16),
              rect: DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 60),
              isNew: true,
              opacity: 1,
              rotation: 0,
            ),
          ),
        );
        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(
          UpdateElementsStyle(elementIds: [draftId], fontSize: 30),
        );

        final interaction = store.state.application.interaction;
        expect(store.state.domain, same(before.domain));
        expect(interaction, isA<TextEditingState>());
        final textEditing = interaction as TextEditingState;
        expect(textEditing.draftData.fontSize, 30);
        expect(textEditing.elementId, draftId);
      },
    );

    test(
      'updates only targeted element and preserves untouched instances',
      () async {
        final initialElements = [
          _filterElement('a', 0),
          _filterElement('b', 1),
          _filterElement('c', 2),
        ];
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(elements: initialElements),
            ),
          ),
        );
        addTearDown(store.dispose);

        final beforeElements = store.state.domain.document.elements;

        await store.dispatch(
          UpdateElementsStyle(elementIds: ['b'], opacity: 0.4),
        );

        final afterElements = store.state.domain.document.elements;
        expect(afterElements, hasLength(3));
        expect(afterElements[0], same(beforeElements[0]));
        expect(afterElements[2], same(beforeElements[2]));
        expect(afterElements[1].id, 'b');
        expect(afterElements[1].opacity, 0.4);
      },
    );
  });

  group('ChangeElementsZIndex characterization', () {
    test(
      'bringToFront preserves relative order of selected and unselected',
      () async {
        final store = _createStore(initialState: _stateWithOrderedElements());
        addTearDown(store.dispose);

        await store.dispatch(
          ChangeElementsZIndex(
            elementIds: ['b', 'd'],
            operation: ZIndexOperation.bringToFront,
          ),
        );

        expect(_elementOrder(store), ['a', 'c', 'e', 'b', 'd']);
        expect(_elementZIndexes(store), [0, 1, 2, 3, 4]);
      },
    );

    test(
      'sendToBack preserves relative order for selected and unselected groups',
      () async {
        final store = _createStore(initialState: _stateWithOrderedElements());
        addTearDown(store.dispose);

        await store.dispatch(
          ChangeElementsZIndex(
            elementIds: ['b', 'd'],
            operation: ZIndexOperation.sendToBack,
          ),
        );

        expect(_elementOrder(store), ['b', 'd', 'a', 'c', 'e']);
        expect(_elementZIndexes(store), [0, 1, 2, 3, 4]);
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

DrawState _stateWithOrderedElements() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: [
        _filterElement('a', 0),
        _filterElement('b', 1),
        _filterElement('c', 2),
        _filterElement('d', 3),
        _filterElement('e', 4),
      ],
    ),
  ),
);

ElementState _filterElement(String id, int zIndex) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const FilterData(),
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
