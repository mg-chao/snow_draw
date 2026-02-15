import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('Reducer z-index assignment', () {
    test(
      'DuplicateElements assigns new elements above highest existing zIndex',
      () async {
        final initialState = DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'a',
                  rect: DrawRect(maxX: 10, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 10,
                  data: FilterData(),
                ),
                ElementState(
                  id: 'b',
                  rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 30,
                  data: FilterData(),
                ),
              ],
            ),
          ),
        );
        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        await store.dispatch(DuplicateElements(elementIds: ['a']));

        final elements = store.state.domain.document.elements;
        final duplicated = elements.where(
          (element) => element.id != 'a' && element.id != 'b',
        );

        expect(duplicated, hasLength(1));
        expect(duplicated.single.zIndex, 31);
      },
    );

    test(
      'FinishCreateElement commits with highest existing zIndex + 1',
      () async {
        const newId = 'creating-rect';
        const createRect = DrawRect(minX: 40, minY: 40, maxX: 100, maxY: 100);
        final initialState =
            DrawState(
              domain: DomainState(
                document: DocumentState(
                  elements: const [
                    ElementState(
                      id: 'a',
                      rect: DrawRect(maxX: 10, maxY: 10),
                      rotation: 0,
                      opacity: 1,
                      zIndex: 3,
                      data: FilterData(),
                    ),
                    ElementState(
                      id: 'b',
                      rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
                      rotation: 0,
                      opacity: 1,
                      zIndex: 10,
                      data: FilterData(),
                    ),
                  ],
                ),
              ),
            ).copyWith(
              application: DrawState().application.copyWith(
                interaction: CreatingState(
                  element: const ElementState(
                    id: newId,
                    rect: createRect,
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: RectangleData(),
                  ),
                  startPosition: const DrawPoint(x: 40, y: 40),
                  currentRect: createRect,
                ),
              ),
            );
        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        await store.dispatch(const FinishCreateElement());

        final created = store.state.domain.document.getElementById(newId);
        expect(created, isNotNull);
        expect(created!.zIndex, 11);
      },
    );

    test(
      'FinishTextEdit creates text with highest existing zIndex + 1',
      () async {
        const textId = 'text-new';
        final initialState =
            DrawState(
              domain: DomainState(
                document: DocumentState(
                  elements: const [
                    ElementState(
                      id: 'a',
                      rect: DrawRect(maxX: 10, maxY: 10),
                      rotation: 0,
                      opacity: 1,
                      zIndex: 12,
                      data: FilterData(),
                    ),
                  ],
                ),
              ),
            ).copyWith(
              application: DrawState().application.copyWith(
                interaction: const TextEditingState(
                  elementId: textId,
                  draftData: TextData(),
                  rect: DrawRect(minX: 10, minY: 10, maxX: 120, maxY: 60),
                  isNew: true,
                  opacity: 1,
                  rotation: 0,
                ),
              ),
            );
        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'ignored',
            text: 'hello',
            isNew: true,
          ),
        );

        final created = store.state.domain.document.getElementById(textId);
        expect(created, isNotNull);
        expect(created!.zIndex, 13);
      },
    );
  });

  group('Reducer no-op allocations', () {
    test(
      'UpdateCreatingElement returns original state when geometry is stable',
      () async {
        const start = DrawPoint(x: 50, y: 60);
        const currentRect = DrawRect(minX: 50, minY: 60, maxX: 50, maxY: 60);
        final initialState = DrawState().copyWith(
          application: DrawState().application.copyWith(
            interaction: CreatingState(
              element: const ElementState(
                id: 'creating-1',
                rect: currentRect,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                data: RectangleData(),
              ),
              startPosition: start,
              currentRect: currentRect,
            ),
          ),
        );
        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(
          const UpdateCreatingElement(currentPosition: start),
        );

        expect(store.state, same(before));
        expect(store.state.application.interaction, isA<CreatingState>());
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
