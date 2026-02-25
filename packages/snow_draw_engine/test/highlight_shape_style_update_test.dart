import 'package:snow_draw_engine/draw/actions/actions.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/store/draw_store.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  test(
    'UpdateElementsStyle applies highlightShape for selected highlight',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      const highlightId = 'h1';
      const initialElement = ElementState(
        id: highlightId,
        rect: DrawRect(maxX: 120, maxY: 80),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: HighlightData(),
      );

      final initialState = DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [initialElement]),
          selection: const SelectionState(selectedIds: {highlightId}),
        ),
      );

      final store = DefaultDrawStore(
        context: context,
        initialState: initialState,
      );
      addTearDown(store.dispose);

      await store.dispatch(
        UpdateElementsStyle(
          elementIds: [highlightId],
          highlightShape: HighlightShape.ellipse,
        ),
      );

      final updated = store.state.domain.document
          .getElementById(highlightId)
          ?.data;
      expect(updated, isA<HighlightData>());
      expect((updated! as HighlightData).shape, HighlightShape.ellipse);
    },
  );
}
