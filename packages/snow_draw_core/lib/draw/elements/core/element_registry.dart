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
/// code.
class DefaultElementRegistry implements ElementRegistry {
  /// Creates a new registry instance.
  DefaultElementRegistry();
  final Map<ElementTypeId<ElementData>, ElementDefinition<ElementData>>
  _definitions = {};

  void register<T extends ElementData>(ElementDefinition<T> definition) {
    final typeId = definition.typeId;
    if (_definitions.containsKey(typeId)) {
      throw StateError('Element type "${typeId.value}" is already registered');
    }
    _definitions[typeId] = definition;
  }

  ElementDefinition<T>? get<T extends ElementData>(ElementTypeId<T> typeId) =>
      _definitions[typeId] as ElementDefinition<T>?;

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => _definitions[typeId] as ElementDefinition<T>?;

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) =>
      _definitions.containsKey(typeId);

  ElementDefinition<T> require<T extends ElementData>(ElementTypeId<T> typeId) {
    final definition = _definitions[typeId];
    if (definition == null) {
      throw StateError('Element type "${typeId.value}" is not registered');
    }
    return definition as ElementDefinition<T>;
  }

  ElementTypeRenderer getRenderer<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => require(typeId).renderer;

  ElementHitTester getHitTester<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => require(typeId).hitTester;

  Iterable<ElementDefinition<ElementData>> get all => _definitions.values;

  Iterable<ElementTypeId<ElementData>> get typeIds => _definitions.keys;

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds =>
      _definitions.keys;

  @visibleForTesting
  void clear() => _definitions.clear();

  /// Copies this registry into a new instance.
  DefaultElementRegistry clone() {
    final cloned = DefaultElementRegistry();
    for (final definition in _definitions.values) {
      cloned._definitions[definition.typeId] = definition;
    }
    return cloned;
  }
}
