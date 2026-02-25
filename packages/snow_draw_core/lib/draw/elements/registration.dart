import 'core/element_data.dart';
import 'core/element_definition.dart';
import 'core/element_registry.dart';
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
/// Call this when constructing a draw context to populate its element
/// registry.
void registerBuiltInElements(DefaultElementRegistry registry) {
  for (final definition in _builtInDefinitions) {
    final typeValue = definition.typeId.value;
    if (!registry.supportsTypeValue(typeValue)) {
      registry.register(definition);
    }
  }
}

/// Resolves [elementRegistry] and registers all built-in definitions.
DefaultElementRegistry resolveElementRegistry({
  DefaultElementRegistry? elementRegistry,
}) {
  final resolved = elementRegistry ?? DefaultElementRegistry();
  registerBuiltInElements(resolved);
  return resolved;
}

const List<ElementDefinition<ElementData>> _builtInDefinitions = [
  rectangleDefinition,
  arrowDefinition,
  lineDefinition,
  freeDrawDefinition,
  filterDefinition,
  highlightDefinition,
  textDefinition,
  serialNumberDefinition,
];
