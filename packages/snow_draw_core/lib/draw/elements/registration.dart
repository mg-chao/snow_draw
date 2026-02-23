import '../core/draw_context.dart' show DrawContext;
import 'core/element_data.dart';
import 'core/element_definition.dart';
import 'core/element_registry.dart';
import 'core/element_registry_interface.dart';
import 'types/arrow/arrow_definition.dart';
import 'types/filter/filter_definition.dart';
import 'types/free_draw/free_draw_definition.dart';
import 'types/highlight/highlight_definition.dart';
import 'types/line/line_definition.dart';
import 'types/rectangle/rectangle_definition.dart';
import 'types/serial_number/serial_number_definition.dart';
import 'types/text/text_definition.dart';

/// Registers all built-in element types.
///
/// Call this when constructing a [DrawContext] to populate its
/// `elementRegistry`.
void registerBuiltInElements(MutableElementRegistry registry) {
  for (final definition in _builtInDefinitions) {
    final typeValue = definition.typeId.value;
    if (!registry.supportsTypeValue(typeValue)) {
      registry.register(definition);
    }
  }
}

/// Resolves [elementRegistry] and optionally registers built-in definitions.
///
/// When [registerBuiltInElementDefinitions] is `true`, the resolved registry
/// must implement [MutableElementRegistry].
ElementRegistry resolveElementRegistry({
  ElementRegistry? elementRegistry,
  bool registerBuiltInElementDefinitions = true,
}) {
  final resolved = elementRegistry ?? DefaultElementRegistry();
  if (!registerBuiltInElementDefinitions) {
    return resolved;
  }
  if (resolved is! MutableElementRegistry) {
    throw ArgumentError.value(
      elementRegistry,
      'elementRegistry',
      'registerBuiltInElementDefinitions=true requires '
          'MutableElementRegistry',
    );
  }
  registerBuiltInElements(resolved);
  return resolved;
}

final List<ElementDefinition<ElementData>> _builtInDefinitions = [
  rectangleDefinition,
  arrowDefinition,
  lineDefinition,
  freeDrawDefinition,
  filterDefinition,
  highlightDefinition,
  textDefinition,
  serialNumberDefinition,
];
