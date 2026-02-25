import 'package:snow_draw_engine/draw/actions/actions.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:snow_draw_engine/draw/elements/types/filter/filter_data.dart';
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

      final store = DefaultDrawStore(
        context: context,
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(elements: const [initialElement]),
            selection: const SelectionState(selectedIds: {filterId}),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        UpdateElementsStyle(
          elementIds: [filterId],
          filterType: CanvasFilterType.gaussianBlur,
          filterStrength: 0.9,
        ),
      );

      final updatedFilter =
          store.state.domain.document.getElementById(filterId)!.data
              as FilterData;
      expect(
        updatedFilter,
        const FilterData(type: CanvasFilterType.gaussianBlur, strength: 0.9),
      );
    },
  );
}
