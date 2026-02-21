import 'package:meta/meta.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import 'element_visual_definition.dart';

/// Registry contract for backend element visual lookups.
abstract interface class ElementVisualRegistry {
  /// Gets visual metadata by strongly typed element id.
  ElementVisualDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  );

  /// Gets visual metadata by serialized type value.
  ElementVisualDefinition<ElementData>? getDefinitionByValue(String typeValue);

  /// Whether visuals are registered for [typeValue].
  bool supportsTypeValue(String typeValue);
}

/// Mutable default registry for backend visual definitions.
class DefaultElementVisualRegistry implements ElementVisualRegistry {
  /// Creates an empty visual registry.
  DefaultElementVisualRegistry();

  final Map<String, ElementVisualDefinition<ElementData>>
  _definitionsByTypeValue = {};

  /// Registers [definition] for its element type id.
  void register<T extends ElementData>(ElementVisualDefinition<T> definition) {
    final typeValue = definition.typeId.value;
    if (_definitionsByTypeValue.containsKey(typeValue)) {
      throw StateError(
        'Element visual type "$typeValue" is already registered',
      );
    }
    _definitionsByTypeValue[typeValue] = definition;
  }

  @override
  ElementVisualDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) {
    final definition = _definitionsByTypeValue[typeId.value];
    return definition is ElementVisualDefinition<T> ? definition : null;
  }

  @override
  ElementVisualDefinition<ElementData>? getDefinitionByValue(
    String typeValue,
  ) => _definitionsByTypeValue[typeValue];

  @override
  bool supportsTypeValue(String typeValue) =>
      _definitionsByTypeValue.containsKey(typeValue);

  /// Returns a shallow copy of this registry.
  DefaultElementVisualRegistry clone() {
    final cloned = DefaultElementVisualRegistry();
    cloned._definitionsByTypeValue.addAll(_definitionsByTypeValue);
    return cloned;
  }

  @visibleForTesting
  void clear() => _definitionsByTypeValue.clear();
}
