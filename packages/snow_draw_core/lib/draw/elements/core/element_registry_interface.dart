import 'element_data.dart';
import 'element_definition.dart';
import 'element_type_id.dart';

/// Registry contract for element definition lookup.
abstract interface class ElementRegistry {
  /// Registers [definition] and fails when its type id is already present.
  void register<T extends ElementData>(ElementDefinition<T> definition);

  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  );

  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue);

  bool supports<T extends ElementData>(ElementTypeId<T> typeId);

  bool supportsTypeValue(String typeValue);

  Iterable<ElementTypeId<ElementData>> get registeredTypeIds;
}
