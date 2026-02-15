import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_definition.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry_interface.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_definition.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/store/history_manager.dart';
import 'package:snow_draw_core/draw/store/snapshot.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test(
    'snapshot decoding can resolve element definitions via type value lookup',
    () {
      final manager = HistoryManager();
      final before = DrawState();
      final after = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: const [
              ElementState(
                id: 'e1',
                rect: DrawRect(maxX: 10, maxY: 10),
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                data: FilterData(strength: 0.4),
              ),
            ],
          ),
        ),
      );
      expect(manager.record(_snapshot(before), _snapshot(after)), isTrue);

      final encoded = manager.snapshot().toJson();
      final registry = _ByValueOnlyRegistry({
        filterDefinition.typeId.value: filterDefinition,
      });
      final snapshot = HistoryManagerSnapshot.fromJson(
        encoded,
        elementRegistry: registry,
      );

      final restored = HistoryManager()..restore(snapshot);
      final undone = restored.undo(after);
      expect(undone, isNotNull);
      final redone = restored.redo(undone!);
      expect(redone, isNotNull);
      expect(
        redone!.domain.document.elements.single.data,
        const FilterData(strength: 0.4),
      );
    },
  );
}

PersistentSnapshot _snapshot(DrawState state) =>
    PersistentSnapshot.fromState(state, includeSelection: false);

class _ByValueOnlyRegistry implements ElementRegistry {
  _ByValueOnlyRegistry(this._definitionsByValue);

  final Map<String, ElementDefinition<ElementData>> _definitionsByValue;

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) {
    throw UnsupportedError(
      'Typed getDefinition should not be used for serialized history decoding',
    );
  }

  @override
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue) =>
      _definitionsByValue[typeValue];

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds =>
      _definitionsByValue.values.map((definition) => definition.typeId);

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) {
    throw UnsupportedError(
      'Typed supports should not be used for serialized history decoding',
    );
  }

  @override
  bool supportsTypeValue(String typeValue) =>
      _definitionsByValue.containsKey(typeValue);
}
