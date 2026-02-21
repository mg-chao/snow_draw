import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';

import 'element_visual_definition.dart';
import 'element_visual_registry.dart';

const _rectangleVisual = ElementVisualDefinition<RectangleData>(
  typeId: RectangleData.typeIdToken,
  icon: Icons.rectangle_outlined,
);

const _arrowVisual = ElementVisualDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  icon: Icons.arrow_right_alt,
);

const _lineVisual = ElementVisualDefinition<LineData>(
  typeId: LineData.typeIdToken,
  icon: Icons.show_chart,
);

const _freeDrawVisual = ElementVisualDefinition<FreeDrawData>(
  typeId: FreeDrawData.typeIdToken,
  icon: Icons.brush_outlined,
);

const _filterVisual = ElementVisualDefinition<FilterData>(
  typeId: FilterData.typeIdToken,
  icon: Icons.auto_fix_high,
);

const _highlightVisual = ElementVisualDefinition<HighlightData>(
  typeId: HighlightData.typeIdToken,
  icon: Icons.highlight,
);

const _textVisual = ElementVisualDefinition<TextData>(
  typeId: TextData.typeIdToken,
  icon: Icons.text_fields,
);

const _serialNumberVisual = ElementVisualDefinition<SerialNumberData>(
  typeId: SerialNumberData.typeIdToken,
  icon: Icons.looks_one_outlined,
);

const List<ElementVisualDefinition<ElementData>> _builtInVisuals = [
  _rectangleVisual,
  _arrowVisual,
  _lineVisual,
  _freeDrawVisual,
  _filterVisual,
  _highlightVisual,
  _textVisual,
  _serialNumberVisual,
];

/// Registers built-in Flutter visuals for all core element types.
void registerBuiltInElementVisuals(DefaultElementVisualRegistry registry) {
  for (final visual in _builtInVisuals) {
    final typeValue = visual.typeId.value;
    if (!registry.supportsTypeValue(typeValue)) {
      registry.register(visual);
    }
  }
}

/// Creates a visual registry pre-populated with built-in visuals.
DefaultElementVisualRegistry createDefaultElementVisualRegistry() {
  final registry = DefaultElementVisualRegistry();
  registerBuiltInElementVisuals(registry);
  return registry;
}

/// Shared default visual registry used by backend canvas widgets.
final DefaultElementVisualRegistry builtInElementVisualRegistry =
    createDefaultElementVisualRegistry();
