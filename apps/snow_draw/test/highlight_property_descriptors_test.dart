import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/property_descriptor.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/property_registry.dart';
import 'package:snow_draw/style_toolbar_state.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('highlight properties appear in the expected order', () {
    initializePropertyRegistry();

    const highlightValues = HighlightStyleValues(
      color: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      highlightShape: MixedValue(
        value: HighlightShape.rectangle,
        isMixed: false,
      ),
      textStrokeColor: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      textStrokeWidth: MixedValue(value: 0, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    );

    const context = StylePropertyContext(
      rectangleStyleValues: RectangleStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        cornerRadius: MixedValue(value: 4, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      arrowStyleValues: ArrowStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        arrowType: MixedValue(value: ArrowType.straight, isMixed: false),
        startArrowhead: MixedValue(value: ArrowheadStyle.none, isMixed: false),
        endArrowhead: MixedValue(
          value: ArrowheadStyle.standard,
          isMixed: false,
        ),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      lineStyleValues: LineStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      freeDrawStyleValues: LineStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      textStyleValues: TextStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fontSize: MixedValue(value: 16, isMixed: false),
        fontFamily: MixedValue(value: '', isMixed: false),
        horizontalAlign: MixedValue(
          value: TextHorizontalAlign.left,
          isMixed: false,
        ),
        verticalAlign: MixedValue(
          value: TextVerticalAlign.center,
          isMixed: false,
        ),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        textStrokeColor: MixedValue(value: Color(0xFFF8F4EC), isMixed: false),
        textStrokeWidth: MixedValue(value: 0, isMixed: false),
        cornerRadius: MixedValue(value: 0, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      serialNumberStyleValues: SerialNumberStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        fontSize: MixedValue(value: 16, isMixed: false),
        fontFamily: MixedValue(value: '', isMixed: false),
        number: MixedValue(value: 1, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      highlightStyleValues: highlightValues,
      rectangleDefaults: ElementStyleConfig(),
      arrowDefaults: ElementStyleConfig(),
      lineDefaults: ElementStyleConfig(),
      freeDrawDefaults: ElementStyleConfig(),
      textDefaults: ElementStyleConfig(),
      serialNumberDefaults: ElementStyleConfig(),
      highlightDefaults: ElementStyleConfig(
        color: Color(0xFFF5222D),
        textStrokeColor: Color(0xFFF5222D),
      ),
      highlightMask: HighlightMaskConfig(maskOpacity: 0.4),
      selectedElementTypes: {ElementType.highlight},
      currentTool: ToolType.highlight,
    );

    final properties = PropertyRegistry.instance.getApplicableProperties(
      context,
    );
    final ids = properties.map((p) => p.id).toList();

    expect(ids, [
      'color',
      'highlightShape',
      'highlightTextStrokeWidth',
      'highlightTextStrokeColor',
      'opacity',
      'maskColor',
      'maskOpacity',
    ]);
  });
}
