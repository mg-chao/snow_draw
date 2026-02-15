import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/property_descriptor.dart';
import 'package:snow_draw/property_descriptors.dart';
import 'package:snow_draw/style_toolbar_state.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('property descriptors', () {
    test('color descriptor merges equal values as non-mixed', () {
      const descriptor = ColorPropertyDescriptor();
      final context = const _PropertyContextFactory(
        selectedElementTypes: {ElementType.rectangle, ElementType.text},
      ).build();

      final value = descriptor.extractValue(context);

      expect(value.isMixed, isFalse);
      expect(value.value, const Color(0xFF000000));
    });

    test('color descriptor marks mixed values across selected elements', () {
      const descriptor = ColorPropertyDescriptor();
      final context = const _PropertyContextFactory(
        selectedElementTypes: {ElementType.rectangle, ElementType.text},
        textColor: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      ).build();

      final value = descriptor.extractValue(context);

      expect(value.isMixed, isTrue);
      expect(value.value, isNull);
    });

    test('color default keeps rectangle precedence'
        ' when rectangle and text selected', () {
      const descriptor = ColorPropertyDescriptor();
      final context = const _PropertyContextFactory(
        selectedElementTypes: {ElementType.rectangle, ElementType.text},
        rectangleDefaults: ElementStyleConfig(color: Color(0xFF1677FF)),
        textDefaults: ElementStyleConfig(color: Color(0xFF52C41A)),
      ).build();

      expect(descriptor.getDefaultValue(context), const Color(0xFF1677FF));
    });

    test('font family descriptor treats all-null values as non-mixed', () {
      const descriptor = FontFamilyPropertyDescriptor();
      final context = const _PropertyContextFactory(
        selectedElementTypes: {ElementType.text, ElementType.serialNumber},
        textFontFamily: MixedValue(value: null, isMixed: false),
        serialNumberFontFamily: MixedValue(value: null, isMixed: false),
      ).build();

      final value = descriptor.extractValue(context);

      expect(value.isMixed, isFalse);
      expect(value.value, isNull);
    });

    test('font family descriptor marks null + non-null values as mixed', () {
      const descriptor = FontFamilyPropertyDescriptor();
      final context = const _PropertyContextFactory(
        selectedElementTypes: {ElementType.text, ElementType.serialNumber},
        textFontFamily: MixedValue(value: null, isMixed: false),
        serialNumberFontFamily: MixedValue(value: 'Roboto', isMixed: false),
      ).build();

      final value = descriptor.extractValue(context);

      expect(value.isMixed, isTrue);
      expect(value.value, isNull);
    });
  });
}

class _PropertyContextFactory {
  const _PropertyContextFactory({
    required this.selectedElementTypes,
    this.textColor = const MixedValue(value: Color(0xFF000000), isMixed: false),
    this.textFontFamily = const MixedValue(value: '', isMixed: false),
    this.serialNumberFontFamily = const MixedValue(value: '', isMixed: false),
    this.rectangleDefaults = const ElementStyleConfig(),
    this.textDefaults = const ElementStyleConfig(),
  });

  final Set<ElementType> selectedElementTypes;
  final MixedValue<Color> textColor;
  final MixedValue<String> textFontFamily;
  final MixedValue<String> serialNumberFontFamily;
  final ElementStyleConfig rectangleDefaults;
  final ElementStyleConfig textDefaults;

  StylePropertyContext build() => StylePropertyContext(
    rectangleStyleValues: const RectangleStyleValues(
      color: MixedValue(value: Color(0xFF000000), isMixed: false),
      fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
      strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
      fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
      strokeWidth: MixedValue(value: 2, isMixed: false),
      cornerRadius: MixedValue(value: 4, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    ),
    arrowStyleValues: const ArrowStyleValues(
      color: MixedValue(value: Color(0xFF000000), isMixed: false),
      strokeWidth: MixedValue(value: 2, isMixed: false),
      strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
      arrowType: MixedValue(value: ArrowType.straight, isMixed: false),
      startArrowhead: MixedValue(value: ArrowheadStyle.none, isMixed: false),
      endArrowhead: MixedValue(value: ArrowheadStyle.standard, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    ),
    lineStyleValues: const LineStyleValues(
      color: MixedValue(value: Color(0xFF000000), isMixed: false),
      fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
      fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
      strokeWidth: MixedValue(value: 2, isMixed: false),
      strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    ),
    freeDrawStyleValues: const LineStyleValues(
      color: MixedValue(value: Color(0xFF000000), isMixed: false),
      fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
      fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
      strokeWidth: MixedValue(value: 2, isMixed: false),
      strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    ),
    textStyleValues: TextStyleValues(
      color: textColor,
      fontSize: const MixedValue(value: 16, isMixed: false),
      fontFamily: textFontFamily,
      horizontalAlign: const MixedValue(
        value: TextHorizontalAlign.left,
        isMixed: false,
      ),
      verticalAlign: const MixedValue(
        value: TextVerticalAlign.center,
        isMixed: false,
      ),
      fillColor: const MixedValue(value: Color(0x00000000), isMixed: false),
      fillStyle: const MixedValue(value: FillStyle.solid, isMixed: false),
      textStrokeColor: const MixedValue(
        value: Color(0xFFF8F4EC),
        isMixed: false,
      ),
      textStrokeWidth: const MixedValue(value: 0, isMixed: false),
      cornerRadius: const MixedValue(value: 0, isMixed: false),
      opacity: const MixedValue(value: 1, isMixed: false),
    ),
    highlightStyleValues: const HighlightStyleValues(
      color: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      highlightShape: MixedValue(
        value: HighlightShape.rectangle,
        isMixed: false,
      ),
      textStrokeColor: MixedValue(value: Color(0xFF000000), isMixed: false),
      textStrokeWidth: MixedValue(value: 0, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    ),
    filterStyleValues: const FilterStyleValues(
      filterType: MixedValue(value: CanvasFilterType.mosaic, isMixed: false),
      filterStrength: MixedValue(value: 0.5, isMixed: false),
    ),
    serialNumberStyleValues: SerialNumberStyleValues(
      color: const MixedValue(value: Color(0xFF000000), isMixed: false),
      fillColor: const MixedValue(value: Color(0x00000000), isMixed: false),
      fillStyle: const MixedValue(value: FillStyle.solid, isMixed: false),
      fontSize: const MixedValue(value: 16, isMixed: false),
      fontFamily: serialNumberFontFamily,
      number: const MixedValue(value: 1, isMixed: false),
      opacity: const MixedValue(value: 1, isMixed: false),
    ),
    rectangleDefaults: rectangleDefaults,
    arrowDefaults: const ElementStyleConfig(),
    lineDefaults: const ElementStyleConfig(),
    freeDrawDefaults: const ElementStyleConfig(),
    textDefaults: textDefaults,
    highlightDefaults: const ElementStyleConfig(),
    filterDefaults: const ElementStyleConfig(),
    serialNumberDefaults: const ElementStyleConfig(),
    highlightMask: const HighlightMaskConfig(maskOpacity: 0.4),
    selectedElementTypes: selectedElementTypes,
  );
}
