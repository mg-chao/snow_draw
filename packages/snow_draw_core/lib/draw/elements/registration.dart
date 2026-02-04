import '../core/core.dart' show DrawContext;
import '../core/draw_context.dart' show DrawContext;
import 'core/element_registry.dart';
import 'types/arrow/arrow_definition.dart';
import 'types/free_draw/free_draw_definition.dart';
import 'types/line/line_definition.dart';
import 'types/rectangle/rectangle_definition.dart';
import 'types/serial_number/serial_number_definition.dart';
import 'types/text/text_definition.dart';

/// Registers all built-in element types.
///
/// Call this when constructing a [DrawContext] to populate its
/// `elementRegistry`.
void registerBuiltInElements(DefaultElementRegistry registry) {
  if (registry.get(rectangleDefinition.typeId) == null) {
    registry.register(rectangleDefinition);
  }
  if (registry.get(arrowDefinition.typeId) == null) {
    registry.register(arrowDefinition);
  }
  if (registry.get(lineDefinition.typeId) == null) {
    registry.register(lineDefinition);
  }
  if (registry.get(freeDrawDefinition.typeId) == null) {
    registry.register(freeDrawDefinition);
  }
  if (registry.get(textDefinition.typeId) == null) {
    registry.register(textDefinition);
  }
  if (registry.get(serialNumberDefinition.typeId) == null) {
    registry.register(serialNumberDefinition);
  }
}
