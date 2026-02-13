import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/property_descriptor.dart';
import 'package:snow_draw/property_registry.dart';
import 'package:snow_draw/style_toolbar_state.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  setUp(PropertyRegistry.instance.clear);

  tearDown(PropertyRegistry.instance.clear);

  test('registration preserves insertion order for applicable properties', () {
    const rectangleOnly = _TestPropertyDescriptor(
      id: 'rectangleOnly',
      supportedElementTypes: {ElementType.rectangle},
      defaultValue: 1,
    );
    const textOnly = _TestPropertyDescriptor(
      id: 'textOnly',
      supportedElementTypes: {ElementType.text},
      defaultValue: 2,
    );
    const shared = _TestPropertyDescriptor(
      id: 'shared',
      supportedElementTypes: {ElementType.rectangle, ElementType.text},
      defaultValue: 3,
    );

    PropertyRegistry.instance
      ..register(rectangleOnly)
      ..register(textOnly)
      ..register(shared);

    final context = _buildContext(selectedElementTypes: {ElementType.text});
    final ids = PropertyRegistry.instance
        .getApplicableProperties(context)
        .map((property) => property.id)
        .toList();

    expect(ids, ['textOnly', 'shared']);
  });

  test('registering an existing property id replaces the descriptor', () {
    const first = _TestPropertyDescriptor(
      id: 'shared',
      supportedElementTypes: {ElementType.rectangle},
      defaultValue: 1,
    );
    const trailing = _TestPropertyDescriptor(
      id: 'trailing',
      supportedElementTypes: {ElementType.text},
      defaultValue: 4,
    );
    const replacement = _TestPropertyDescriptor(
      id: 'shared',
      supportedElementTypes: {ElementType.text},
      defaultValue: 9,
    );

    PropertyRegistry.instance
      ..register(first)
      ..register(trailing)
      ..register(replacement);

    final rectangleContext = _buildContext(
      selectedElementTypes: {ElementType.rectangle},
    );
    final textContext = _buildContext(selectedElementTypes: {ElementType.text});

    expect(
      PropertyRegistry.instance.allProperties.map((property) => property.id),
      ['shared', 'trailing'],
    );
    expect(PropertyRegistry.instance.getProperty('shared'), same(replacement));
    expect(
      PropertyRegistry.instance.getApplicableProperties(rectangleContext),
      isEmpty,
    );
    expect(
      PropertyRegistry.instance
          .getApplicableProperties(textContext)
          .map((property) => property.id),
      ['shared', 'trailing'],
    );
  });
}

class _TestPropertyDescriptor extends PropertyDescriptor<int> {
  const _TestPropertyDescriptor({
    required super.id,
    required super.supportedElementTypes,
    required this.defaultValue,
  });

  final int defaultValue;

  @override
  MixedValue<int> extractValue(StylePropertyContext context) =>
      MixedValue(value: defaultValue, isMixed: false);

  @override
  int getDefaultValue(StylePropertyContext context) => defaultValue;
}

StylePropertyContext _buildContext({
  required Set<ElementType> selectedElementTypes,
}) => StylePropertyContext(
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
  textStyleValues: const TextStyleValues(
    color: MixedValue(value: Color(0xFF000000), isMixed: false),
    fontSize: MixedValue(value: 16, isMixed: false),
    fontFamily: MixedValue(value: '', isMixed: false),
    horizontalAlign: MixedValue(
      value: TextHorizontalAlign.left,
      isMixed: false,
    ),
    verticalAlign: MixedValue(value: TextVerticalAlign.center, isMixed: false),
    fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
    fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
    textStrokeColor: MixedValue(value: Color(0xFFF8F4EC), isMixed: false),
    textStrokeWidth: MixedValue(value: 0, isMixed: false),
    cornerRadius: MixedValue(value: 0, isMixed: false),
    opacity: MixedValue(value: 1, isMixed: false),
  ),
  highlightStyleValues: const HighlightStyleValues(
    color: MixedValue(value: Color(0xFFF5222D), isMixed: false),
    highlightShape: MixedValue(value: HighlightShape.rectangle, isMixed: false),
    textStrokeColor: MixedValue(value: Color(0xFF000000), isMixed: false),
    textStrokeWidth: MixedValue(value: 0, isMixed: false),
    opacity: MixedValue(value: 1, isMixed: false),
  ),
  filterStyleValues: const FilterStyleValues(
    filterType: MixedValue(value: CanvasFilterType.mosaic, isMixed: false),
    filterStrength: MixedValue(value: 0.5, isMixed: false),
  ),
  serialNumberStyleValues: const SerialNumberStyleValues(
    color: MixedValue(value: Color(0xFF000000), isMixed: false),
    fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
    fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
    fontSize: MixedValue(value: 16, isMixed: false),
    fontFamily: MixedValue(value: '', isMixed: false),
    number: MixedValue(value: 1, isMixed: false),
    opacity: MixedValue(value: 1, isMixed: false),
  ),
  rectangleDefaults: const ElementStyleConfig(),
  arrowDefaults: const ElementStyleConfig(),
  lineDefaults: const ElementStyleConfig(),
  freeDrawDefaults: const ElementStyleConfig(),
  textDefaults: const ElementStyleConfig(),
  highlightDefaults: const ElementStyleConfig(),
  filterDefaults: const ElementStyleConfig(),
  serialNumberDefaults: const ElementStyleConfig(),
  highlightMask: const HighlightMaskConfig(maskOpacity: 0.4),
  selectedElementTypes: selectedElementTypes,
);
