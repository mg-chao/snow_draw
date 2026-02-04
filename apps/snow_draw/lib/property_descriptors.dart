import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'property_descriptor.dart';
import 'property_utils.dart';
import 'style_toolbar_state.dart';

/// Property descriptor for stroke color
class ColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const ColorPropertyDescriptor()
    : super(
        id: 'color',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    final values = <MixedValue<Color>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.color);
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      values.add(context.arrowStyleValues.color);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.color);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.color);
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.color);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.color);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.colorEquals);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.color;
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowDefaults.color;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.color;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.color;
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.color;
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.color;
    }
    return Colors.black;
  }
}

/// Property descriptor for stroke width
class StrokeWidthPropertyDescriptor extends PropertyDescriptor<double> {
  const StrokeWidthPropertyDescriptor()
    : super(
        id: 'strokeWidth',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
        },
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    final values = <MixedValue<double>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.strokeWidth);
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      values.add(context.arrowStyleValues.strokeWidth);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.strokeWidth);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.strokeWidth);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.doubleEquals);
  }

  @override
  double getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.strokeWidth;
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowDefaults.strokeWidth;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.strokeWidth;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.strokeWidth;
    }
    return 2;
  }
}

/// Property descriptor for stroke style
class StrokeStylePropertyDescriptor extends PropertyDescriptor<StrokeStyle> {
  const StrokeStylePropertyDescriptor()
    : super(
        id: 'strokeStyle',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
        },
      );

  @override
  MixedValue<StrokeStyle> extractValue(StylePropertyContext context) {
    final values = <MixedValue<StrokeStyle>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.strokeStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      values.add(context.arrowStyleValues.strokeStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.strokeStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.strokeStyle);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.enumEquals);
  }

  @override
  StrokeStyle getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.strokeStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowDefaults.strokeStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.strokeStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.strokeStyle;
    }
    return StrokeStyle.solid;
  }
}

/// Property descriptor for fill color
class FillColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const FillColorPropertyDescriptor()
    : super(
        id: 'fillColor',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    final values = <MixedValue<Color>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.fillColor);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.fillColor);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.fillColor);
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.fillColor);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.fillColor);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.colorEquals);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.fillColor;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.fillColor;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.fillColor;
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.fillColor;
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.fillColor;
    }
    return Colors.transparent;
  }
}

/// Property descriptor for fill style
class FillStylePropertyDescriptor extends PropertyDescriptor<FillStyle> {
  const FillStylePropertyDescriptor()
    : super(
        id: 'fillStyle',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  @override
  MixedValue<FillStyle> extractValue(StylePropertyContext context) {
    final values = <MixedValue<FillStyle>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.fillStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.fillStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.fillStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.fillStyle);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.fillStyle);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.enumEquals);
  }

  @override
  FillStyle getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.fillStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.fillStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.fillStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.fillStyle;
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.fillStyle;
    }
    return FillStyle.solid;
  }
}

/// Property descriptor for opacity
class OpacityPropertyDescriptor extends PropertyDescriptor<double> {
  const OpacityPropertyDescriptor()
    : super(
        id: 'opacity',
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    final values = <MixedValue<double>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.opacity);
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      values.add(context.arrowStyleValues.opacity);
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      values.add(context.lineStyleValues.opacity);
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      values.add(context.freeDrawStyleValues.opacity);
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.opacity);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.opacity);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.doubleEquals);
  }

  @override
  double getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.opacity;
    }
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowDefaults.opacity;
    }
    if (context.selectedElementTypes.contains(ElementType.line)) {
      return context.lineDefaults.opacity;
    }
    if (context.selectedElementTypes.contains(ElementType.freeDraw)) {
      return context.freeDrawDefaults.opacity;
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.opacity;
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.opacity;
    }
    return 1;
  }
}

/// Property descriptor for corner radius
class CornerRadiusPropertyDescriptor extends PropertyDescriptor<double> {
  const CornerRadiusPropertyDescriptor()
    : super(
        id: 'cornerRadius',
        supportedElementTypes: const {ElementType.rectangle, ElementType.text},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    final values = <MixedValue<double>>[];

    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      values.add(context.rectangleStyleValues.cornerRadius);
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.cornerRadius);
    }

    if (values.isEmpty) {
      return const MixedValue(value: null, isMixed: true);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.doubleEquals);
  }

  @override
  double getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.rectangle)) {
      return context.rectangleDefaults.cornerRadius;
    }
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.cornerRadius;
    }
    return 0;
  }
}

/// Property descriptor for font size
class FontSizePropertyDescriptor extends PropertyDescriptor<double> {
  const FontSizePropertyDescriptor()
    : super(
        id: 'fontSize',
        supportedElementTypes: const {ElementType.text, ElementType.serialNumber},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    final values = <MixedValue<double>>[];

    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.fontSize);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.fontSize);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.doubleEquals);
  }

  @override
  double getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.fontSize;
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.fontSize;
    }
    return context.textDefaults.fontSize;
  }
}

/// Property descriptor for font family
class FontFamilyPropertyDescriptor extends PropertyDescriptor<String> {
  const FontFamilyPropertyDescriptor()
    : super(
        id: 'fontFamily',
        supportedElementTypes: const {ElementType.text, ElementType.serialNumber},
      );

  @override
  MixedValue<String> extractValue(StylePropertyContext context) {
    final values = <MixedValue<String>>[];

    if (context.selectedElementTypes.contains(ElementType.text)) {
      values.add(context.textStyleValues.fontFamily);
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      values.add(context.serialNumberStyleValues.fontFamily);
    }

    return PropertyUtils.mergeMixedValues(values, PropertyUtils.stringEquals);
  }

  @override
  String getDefaultValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textDefaults.fontFamily ?? 'Arial';
    }
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberDefaults.fontFamily ?? 'Arial';
    }
    return context.textDefaults.fontFamily ?? 'Arial';
  }
}

/// Property descriptor for serial number value
class SerialNumberPropertyDescriptor extends PropertyDescriptor<int> {
  const SerialNumberPropertyDescriptor()
    : super(
        id: 'serialNumber',
        supportedElementTypes: const {ElementType.serialNumber},
      );

  @override
  MixedValue<int> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.serialNumber)) {
      return context.serialNumberStyleValues.number;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  int getDefaultValue(StylePropertyContext context) =>
      context.serialNumberDefaults.serialNumber;
}

/// Property descriptor for text alignment
class TextAlignPropertyDescriptor
    extends PropertyDescriptor<TextHorizontalAlign> {
  const TextAlignPropertyDescriptor()
    : super(id: 'textAlign', supportedElementTypes: const {ElementType.text});

  @override
  MixedValue<TextHorizontalAlign> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textStyleValues.horizontalAlign;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  TextHorizontalAlign getDefaultValue(StylePropertyContext context) =>
      context.textDefaults.textAlign;
}

/// Property descriptor for arrowhead style
class ArrowheadPropertyDescriptor extends PropertyDescriptor<ArrowheadStyle> {
  const ArrowheadPropertyDescriptor()
    : super(id: 'arrowhead', supportedElementTypes: const {ElementType.arrow});

  @override
  MixedValue<ArrowheadStyle> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowStyleValues.endArrowhead;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  ArrowheadStyle getDefaultValue(StylePropertyContext context) =>
      context.arrowDefaults.endArrowhead;
}

/// Property descriptor for start arrowhead style
class StartArrowheadPropertyDescriptor
    extends PropertyDescriptor<ArrowheadStyle> {
  const StartArrowheadPropertyDescriptor()
    : super(
        id: 'startArrowhead',
        supportedElementTypes: const {ElementType.arrow},
      );

  @override
  MixedValue<ArrowheadStyle> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowStyleValues.startArrowhead;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  ArrowheadStyle getDefaultValue(StylePropertyContext context) =>
      context.arrowDefaults.startArrowhead;
}

/// Property descriptor for end arrowhead style
class EndArrowheadPropertyDescriptor
    extends PropertyDescriptor<ArrowheadStyle> {
  const EndArrowheadPropertyDescriptor()
    : super(
        id: 'endArrowhead',
        supportedElementTypes: const {ElementType.arrow},
      );

  @override
  MixedValue<ArrowheadStyle> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowStyleValues.endArrowhead;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  ArrowheadStyle getDefaultValue(StylePropertyContext context) =>
      context.arrowDefaults.endArrowhead;
}

/// Property descriptor for arrow type
class ArrowTypePropertyDescriptor extends PropertyDescriptor<ArrowType> {
  const ArrowTypePropertyDescriptor()
    : super(id: 'arrowType', supportedElementTypes: const {ElementType.arrow});

  @override
  MixedValue<ArrowType> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.arrow)) {
      return context.arrowStyleValues.arrowType;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  ArrowType getDefaultValue(StylePropertyContext context) =>
      context.arrowDefaults.arrowType;
}

/// Property descriptor for text stroke color
class TextStrokeColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const TextStrokeColorPropertyDescriptor()
    : super(
        id: 'textStrokeColor',
        supportedElementTypes: const {ElementType.text},
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textStyleValues.textStrokeColor;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) =>
      context.textDefaults.textStrokeColor;
}

/// Property descriptor for text stroke width
class TextStrokeWidthPropertyDescriptor extends PropertyDescriptor<double> {
  const TextStrokeWidthPropertyDescriptor()
    : super(
        id: 'textStrokeWidth',
        supportedElementTypes: const {ElementType.text},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.text)) {
      return context.textStyleValues.textStrokeWidth;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  double getDefaultValue(StylePropertyContext context) =>
      context.textDefaults.textStrokeWidth;
}
