import 'element_data.dart';
import 'element_definition.dart';
import 'element_type_id.dart';

/// ElementRegistry abstraction for testability.
abstract interface class ElementRegistry {
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  );

  /// Looks up a definition using the raw type value.
  ///
  /// This avoids allocating an [ElementTypeId] when the caller already has
  /// the serialized type string.
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue);

  bool supports<T extends ElementData>(ElementTypeId<T> typeId);

  /// Returns whether [typeValue] is currently registered.
  bool supportsTypeValue(String typeValue);

  Iterable<ElementTypeId<ElementData>> get registeredTypeIds;
}
