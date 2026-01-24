import 'element_data.dart';
import 'element_definition.dart';
import 'element_type_id.dart';

/// ElementRegistry abstraction for testability.
abstract interface class ElementRegistry {
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  );
  bool supports<T extends ElementData>(ElementTypeId<T> typeId);
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds;
}
