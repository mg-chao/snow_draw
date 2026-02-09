import 'property_descriptors.dart';
import 'property_registry.dart';

/// Initialize the property registry with all available properties
void initializePropertyRegistry() {
  PropertyRegistry.instance
    // Clear any existing properties (useful for hot reload)
    ..clear()
    // Register all property descriptors in the order they should appear
    // in the toolbar
    // Color and fill properties
    ..register(const ColorPropertyDescriptor())
    ..register(const FillColorPropertyDescriptor())
    ..register(const FillStylePropertyDescriptor())
    // Stroke properties
    ..register(const StrokeWidthPropertyDescriptor())
    ..register(const StrokeStylePropertyDescriptor())
    // Highlight-specific properties
    ..register(const HighlightShapePropertyDescriptor())
    // Arrow-specific properties
    ..register(const ArrowTypePropertyDescriptor())
    ..register(const StartArrowheadPropertyDescriptor())
    ..register(const EndArrowheadPropertyDescriptor())
    // Text properties
    ..register(const SerialNumberPropertyDescriptor())
    ..register(const FontSizePropertyDescriptor())
    ..register(const FontFamilyPropertyDescriptor())
    ..register(const TextAlignPropertyDescriptor())
    // Stroke text properties
    ..register(const HighlightTextStrokeWidthPropertyDescriptor())
    ..register(const HighlightTextStrokeColorPropertyDescriptor())
    ..register(const TextStrokeWidthPropertyDescriptor())
    ..register(const TextStrokeColorPropertyDescriptor())
    // Common properties (all elements)
    ..register(const CornerRadiusPropertyDescriptor())
    ..register(const OpacityPropertyDescriptor())
    ..register(const MaskColorPropertyDescriptor())
    ..register(const MaskOpacityPropertyDescriptor());
}
