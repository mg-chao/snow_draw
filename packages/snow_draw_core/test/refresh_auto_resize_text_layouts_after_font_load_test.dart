import 'package:test/test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_editing_geometry.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('RefreshAutoResizeTextLayoutsAfterFontLoad', () {
    test('recomputes bounds for auto-resize text elements', () async {
      const data = TextData(
        text: '瀛椾綋鍔犺浇鍚庡簲閲嶆柊璁＄畻瀹藉害',
        fontSize: 42,
        autoResize: true,
      );
      const initialRect = DrawRect(minX: 40, minY: 70, maxX: 80, maxY: 95);
      final expectedRect = _expectedAutoResizeRect(
        originX: initialRect.minX,
        originY: initialRect.minY,
        data: data,
      );

      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'text-auto',
                  rect: initialRect,
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: data,
                ),
              ],
            ),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(const RefreshAutoResizeTextLayoutsAfterFontLoad());
      final updated = store.state.domain.document.getElementById('text-auto');
      expect(updated, isNotNull);
      expect(updated!.rect.minX, closeTo(expectedRect.minX, 0.001));
      expect(updated.rect.minY, closeTo(expectedRect.minY, 0.001));
      expect(updated.rect.maxX, closeTo(expectedRect.maxX, 0.001));
      expect(updated.rect.maxY, closeTo(expectedRect.maxY, 0.001));
    });

    test('does not change non-auto-resize text elements', () async {
      const data = TextData(
        text: 'manual width should stay',
        fontSize: 28,
        autoResize: false,
      );
      const initialRect = DrawRect(minX: 10, minY: 20, maxX: 300, maxY: 80);
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'text-fixed',
                  rect: initialRect,
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: data,
                ),
              ],
            ),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(const RefreshAutoResizeTextLayoutsAfterFontLoad());
      final updated = store.state.domain.document.getElementById('text-fixed');
      expect(updated, isNotNull);
      expect(updated!.rect, initialRect);
    });

    test(
      'recomputes bounds for auto-resize text editing interaction',
      () async {
        const data = TextData(
          text: 'editing draft',
          fontSize: 34,
          autoResize: true,
        );
        const initialRect = DrawRect(
          minX: 100,
          minY: 120,
          maxX: 160,
          maxY: 150,
        );
        final expectedRect = _expectedAutoResizeRect(
          originX: initialRect.minX,
          originY: initialRect.minY,
          data: data,
        );

        final store = _createStore(
          initialState: DrawState(
            application: ApplicationState.initial().copyWith(
              interaction: const TextEditingState(
                elementId: 'editing-auto',
                draftData: data,
                rect: initialRect,
                isNew: true,
                opacity: 1,
                rotation: 0,
              ),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(const RefreshAutoResizeTextLayoutsAfterFontLoad());
        final interaction = store.state.application.interaction;
        expect(interaction, isA<TextEditingState>());
        final editing = interaction as TextEditingState;
        expect(editing.rect.minX, closeTo(expectedRect.minX, 0.001));
        expect(editing.rect.minY, closeTo(expectedRect.minY, 0.001));
        expect(editing.rect.maxX, closeTo(expectedRect.maxX, 0.001));
        expect(editing.rect.maxY, closeTo(expectedRect.maxY, 0.001));
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

DrawRect _expectedAutoResizeRect({
  required double originX,
  required double originY,
  required TextData data,
}) => resolveAutoResizeTextEditingRect(
  origin: DrawPoint(x: originX, y: originY),
  data: data,
);
