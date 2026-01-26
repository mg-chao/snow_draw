import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'style_toolbar_state.dart';
import 'tool_controller.dart';

/// Element types that can be selected
enum ElementType {
  rectangle,
  arrow,
  text,
}

/// Context containing all style information needed for property evaluation
class StylePropertyContext {
  const StylePropertyContext({
    required this.rectangleStyleValues,
    required this.arrowStyleValues,
    required this.textStyleValues,
    required this.rectangleDefaults,
    required this.arrowDefaults,
    required this.textDefaults,
    required this.selectedElementTypes,
    this.currentTool,
  });

  final RectangleStyleValues rectangleStyleValues;
  final ArrowStyleValues arrowStyleValues;
  final TextStyleValues textStyleValues;
  final ElementStyleConfig rectangleDefaults;
  final ElementStyleConfig arrowDefaults;
  final ElementStyleConfig textDefaults;
  final Set<ElementType> selectedElementTypes;
  final ToolType? currentTool;

  /// Check if any of the given element types are selected
  bool hasAnySelected(Set<ElementType> types) {
    return types.any(selectedElementTypes.contains);
  }

  /// Check if all of the given element types are selected
  bool hasAllSelected(Set<ElementType> types) {
    return types.every(selectedElementTypes.contains);
  }

  /// Check if only the given element types are selected (no others)
  bool hasOnlySelected(Set<ElementType> types) {
    return selectedElementTypes.length == types.length &&
        types.every(selectedElementTypes.contains);
  }
}

/// Abstract descriptor for a style property
///
/// Each property knows:
/// - Which element types it applies to
/// - How to extract its value from the context
/// - What its default value is
abstract class PropertyDescriptor<T> {
  const PropertyDescriptor({
    required this.id,
    required this.supportedElementTypes,
  });

  /// Unique identifier for this property
  final String id;

  /// Element types that support this property
  final Set<ElementType> supportedElementTypes;

  /// Check if this property should be shown given the current context
  ///
  /// Default implementation: show if any selected element supports this property
  bool isApplicable(StylePropertyContext context) {
    return context.hasAnySelected(supportedElementTypes);
  }

  /// Extract the current value of this property from the context
  ///
  /// If multiple element types are selected, this should merge their values
  /// using MixedValue semantics
  MixedValue<T> extractValue(StylePropertyContext context);

  /// Get the default value for this property given the context
  ///
  /// If multiple element types are selected, returns the default for the
  /// first supported type
  T getDefaultValue(StylePropertyContext context);
}
