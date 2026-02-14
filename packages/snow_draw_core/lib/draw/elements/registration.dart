import '../core/draw_context.dart' show DrawContext;
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
/// Call this when constructing a [DrawContext] to populate its
/// `elementRegistry`.
void registerBuiltInElements(DefaultElementRegistry registry) {
  _registerIfMissing(registry, rectangleDefinition);
  _registerIfMissing(registry, arrowDefinition);
  _registerIfMissing(registry, lineDefinition);
  _registerIfMissing(registry, freeDrawDefinition);
  _registerIfMissing(registry, filterDefinition);
  _registerIfMissing(registry, highlightDefinition);
  _registerIfMissing(registry, textDefinition);
  _registerIfMissing(registry, serialNumberDefinition);
}

void _registerIfMissing<T extends ElementData>(
  DefaultElementRegistry registry,
  ElementDefinition<T> definition,
) {
  if (registry.supportsTypeValue(definition.typeId.value)) {
    return;
  }
  registry.register(definition);
}
