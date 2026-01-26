import 'property_descriptors.dart';
import 'property_registry.dart';

/// Initialize the property registry with all available properties
void initializePropertyRegistry() {
  final registry = PropertyRegistry.instance;

  // Clear any existing properties (useful for hot reload)
  registry.clear();

  // Register all property descriptors in the order they should appear
  // in the toolbar

  // Color properties (stroke and fill)
  registry.register(const ColorPropertyDescriptor());
  registry.register(const FillColorPropertyDescriptor());
  registry.register(const FillStylePropertyDescriptor());

  // Stroke properties
  registry.register(const StrokeWidthPropertyDescriptor());
  registry.register(const StrokeStylePropertyDescriptor());

  // Arrow-specific properties
  registry.register(const ArrowTypePropertyDescriptor());
  registry.register(const StartArrowheadPropertyDescriptor());
  registry.register(const EndArrowheadPropertyDescriptor());

  // Text properties
  registry.register(const FontSizePropertyDescriptor());
  registry.register(const FontFamilyPropertyDescriptor());
  registry.register(const TextAlignPropertyDescriptor());
  registry.register(const TextStrokeWidthPropertyDescriptor());
  registry.register(const TextStrokeColorPropertyDescriptor());

  // Common properties (all elements)
  registry.register(const CornerRadiusPropertyDescriptor());
  registry.register(const OpacityPropertyDescriptor());
}
