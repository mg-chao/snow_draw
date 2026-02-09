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
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test(
    'UpdateElementsStyle applies filter style for selected filter',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      const filterId = 'f1';
      const initialElement = ElementState(
        id: filterId,
        rect: DrawRect(maxX: 120, maxY: 80),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      );

      final initialState = DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [initialElement]),
          selection: const SelectionState(selectedIds: {filterId}),
        ),
      );

      final store = DefaultDrawStore(
        context: context,
        initialState: initialState,
      );
      addTearDown(store.dispose);

      await store.dispatch(
        const UpdateElementsStyle(
          elementIds: [filterId],
          filterType: CanvasFilterType.gaussianBlur,
          filterStrength: 0.9,
        ),
      );

      final updated = store.state.domain.document
          .getElementById(filterId)
          ?.data;
      expect(updated, isA<FilterData>());
      final filter = updated! as FilterData;
      expect(filter.type, CanvasFilterType.gaussianBlur);
      expect(filter.strength, 0.9);
    },
  );
}
