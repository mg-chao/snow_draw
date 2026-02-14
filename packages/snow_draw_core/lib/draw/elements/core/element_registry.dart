import 'package:meta/meta.dart';

import 'element_data.dart';
import 'element_definition.dart';
import 'element_hit_tester.dart';
import 'element_registry_interface.dart';
import 'element_renderer.dart';
import 'element_type_id.dart';

/// Runtime registry for all element types.
///
/// This enables open/closed behavior: adding a new element type is done by
/// registering a new [ElementDefinition], without modifying core render or
/// hit-test code.
class DefaultElementRegistry implements ElementRegistry {
  /// Creates a new registry instance.
  DefaultElementRegistry();
  final Map<String, ElementDefinition<ElementData>> _definitionsByTypeValue =
      {};

  void register<T extends ElementData>(ElementDefinition<T> definition) {
    final typeValue = definition.typeId.value;
    if (_definitionsByTypeValue.containsKey(typeValue)) {
      throw StateError('Element type "$typeValue" is already registered');
    }
    _definitionsByTypeValue[typeValue] = definition;
  }

  ElementDefinition<T>? get<T extends ElementData>(ElementTypeId<T> typeId) =>
      _getTypedDefinition(typeId.value);

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => _getTypedDefinition(typeId.value);

  @override
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue) =>
      _definitionsByTypeValue[typeValue];

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) =>
      _getTypedDefinition<T>(typeId.value) != null;

  @override
  bool supportsTypeValue(String typeValue) =>
      _definitionsByTypeValue.containsKey(typeValue);

  ElementDefinition<T> require<T extends ElementData>(ElementTypeId<T> typeId) {
    final definition = _getTypedDefinition<T>(typeId.value);
    if (definition == null) {
      throw StateError('Element type "${typeId.value}" is not registered');
    }
    return definition;
  }

  ElementTypeRenderer getRenderer<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => require(typeId).renderer;

  ElementHitTester getHitTester<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => require(typeId).hitTester;

  Iterable<ElementDefinition<ElementData>> get all =>
      _definitionsByTypeValue.values;

  Iterable<ElementTypeId<ElementData>> get typeIds =>
      _definitionsByTypeValue.values.map((definition) => definition.typeId);

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds => typeIds;

  @visibleForTesting
  void clear() => _definitionsByTypeValue.clear();

  /// Copies this registry into a new instance.
  DefaultElementRegistry clone() {
    final cloned = DefaultElementRegistry();
    for (final definition in _definitionsByTypeValue.values) {
      cloned._definitionsByTypeValue[definition.typeId.value] = definition;
    }
    return cloned;
  }

  ElementDefinition<T>? _getTypedDefinition<T extends ElementData>(
    String typeValue,
  ) {
    final definition = _definitionsByTypeValue[typeValue];
    if (definition is ElementDefinition<T>) {
      return definition;
    }
    return null;
  }
}
