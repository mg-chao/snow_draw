import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'property_descriptor.dart';
import 'property_ids.dart';
import 'property_utils.dart';
import 'style_toolbar_state.dart';

class _PropertySource<T> {
  const _PropertySource({
    required this.elementType,
    required this.valueSelector,
    required this.defaultSelector,
  });

  final ElementType elementType;
  final MixedValue<T> Function(StylePropertyContext context) valueSelector;
  final T Function(StylePropertyContext context) defaultSelector;
}

MixedValue<T> _extractMergedValue<T>(
  StylePropertyContext context,
  List<_PropertySource<T>> sources,
  bool Function(T, T) equals, {
  bool treatNullAsValue = false,
}) {
  final values = <MixedValue<T>>[];
  for (final source in sources) {
    if (context.selectedElementTypes.contains(source.elementType)) {
      values.add(source.valueSelector(context));
    }
  }
  return PropertyUtils.mergeMixedValues(
    values,
    equals,
    treatNullAsValue: treatNullAsValue,
  );
}

T _extractDefaultValue<T>(
  StylePropertyContext context,
  List<_PropertySource<T>> sources,
  T fallback,
) {
  for (final source in sources) {
    if (context.selectedElementTypes.contains(source.elementType)) {
      return source.defaultSelector(context);
    }
  }
  return fallback;
}

/// Property descriptor for stroke color
class ColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const ColorPropertyDescriptor()
    : super(
        id: PropertyIds.color,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.highlight,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<Color>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.color,
      defaultSelector: (context) => context.rectangleDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.highlight,
      valueSelector: (context) => context.highlightStyleValues.color,
      defaultSelector: (context) => context.highlightDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.arrow,
      valueSelector: (context) => context.arrowStyleValues.color,
      defaultSelector: (context) => context.arrowDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.color,
      defaultSelector: (context) => context.lineDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.color,
      defaultSelector: (context) => context.freeDrawDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.color,
      defaultSelector: (context) => context.textDefaults.color,
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.color,
      defaultSelector: (context) => context.serialNumberDefaults.color,
    ),
  ];

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.colorEquals);

  @override
  Color getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, Colors.black);
}

/// Property descriptor for highlight shape
class HighlightShapePropertyDescriptor
    extends PropertyDescriptor<HighlightShape> {
  const HighlightShapePropertyDescriptor()
    : super(
        id: PropertyIds.highlightShape,
        supportedElementTypes: const {ElementType.highlight},
      );

  @override
  MixedValue<HighlightShape> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.highlight)) {
      return context.highlightStyleValues.highlightShape;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  HighlightShape getDefaultValue(StylePropertyContext context) =>
      context.highlightDefaults.highlightShape;
}

/// Property descriptor for filter type.
class FilterTypePropertyDescriptor
    extends PropertyDescriptor<CanvasFilterType> {
  const FilterTypePropertyDescriptor()
    : super(
        id: PropertyIds.filterType,
        supportedElementTypes: const {ElementType.filter},
      );

  @override
  MixedValue<CanvasFilterType> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.filter)) {
      return context.filterStyleValues.filterType;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  CanvasFilterType getDefaultValue(StylePropertyContext context) =>
      context.filterDefaults.filterType;
}

/// Property descriptor for filter strength.
class FilterStrengthPropertyDescriptor extends PropertyDescriptor<double> {
  const FilterStrengthPropertyDescriptor()
    : super(
        id: PropertyIds.filterStrength,
        supportedElementTypes: const {ElementType.filter},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.filter)) {
      return context.filterStyleValues.filterStrength;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  double getDefaultValue(StylePropertyContext context) =>
      context.filterDefaults.filterStrength;
}

/// Property descriptor for highlight text stroke width
class HighlightTextStrokeWidthPropertyDescriptor
    extends PropertyDescriptor<double> {
  const HighlightTextStrokeWidthPropertyDescriptor()
    : super(
        id: PropertyIds.highlightTextStrokeWidth,
        supportedElementTypes: const {ElementType.highlight},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.highlight)) {
      return context.highlightStyleValues.textStrokeWidth;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  double getDefaultValue(StylePropertyContext context) =>
      context.highlightDefaults.textStrokeWidth;
}

/// Property descriptor for highlight text stroke color
class HighlightTextStrokeColorPropertyDescriptor
    extends PropertyDescriptor<Color> {
  const HighlightTextStrokeColorPropertyDescriptor()
    : super(
        id: PropertyIds.highlightTextStrokeColor,
        supportedElementTypes: const {ElementType.highlight},
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.highlight)) {
      return context.highlightStyleValues.textStrokeColor;
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) =>
      context.highlightDefaults.textStrokeColor;
}

/// Property descriptor for stroke width
class StrokeWidthPropertyDescriptor extends PropertyDescriptor<double> {
  const StrokeWidthPropertyDescriptor()
    : super(
        id: PropertyIds.strokeWidth,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
        },
      );

  static final List<_PropertySource<double>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.strokeWidth,
      defaultSelector: (context) => context.rectangleDefaults.strokeWidth,
    ),
    _PropertySource(
      elementType: ElementType.arrow,
      valueSelector: (context) => context.arrowStyleValues.strokeWidth,
      defaultSelector: (context) => context.arrowDefaults.strokeWidth,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.strokeWidth,
      defaultSelector: (context) => context.lineDefaults.strokeWidth,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.strokeWidth,
      defaultSelector: (context) => context.freeDrawDefaults.strokeWidth,
    ),
  ];

  @override
  MixedValue<double> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.doubleEquals);

  @override
  double getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, 2);
}

/// Property descriptor for stroke style
class StrokeStylePropertyDescriptor extends PropertyDescriptor<StrokeStyle> {
  const StrokeStylePropertyDescriptor()
    : super(
        id: PropertyIds.strokeStyle,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
        },
      );

  static final List<_PropertySource<StrokeStyle>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.strokeStyle,
      defaultSelector: (context) => context.rectangleDefaults.strokeStyle,
    ),
    _PropertySource(
      elementType: ElementType.arrow,
      valueSelector: (context) => context.arrowStyleValues.strokeStyle,
      defaultSelector: (context) => context.arrowDefaults.strokeStyle,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.strokeStyle,
      defaultSelector: (context) => context.lineDefaults.strokeStyle,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.strokeStyle,
      defaultSelector: (context) => context.freeDrawDefaults.strokeStyle,
    ),
  ];

  @override
  MixedValue<StrokeStyle> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.enumEquals);

  @override
  StrokeStyle getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, StrokeStyle.solid);
}

/// Property descriptor for fill color
class FillColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const FillColorPropertyDescriptor()
    : super(
        id: PropertyIds.fillColor,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<Color>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.fillColor,
      defaultSelector: (context) => context.rectangleDefaults.fillColor,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.fillColor,
      defaultSelector: (context) => context.lineDefaults.fillColor,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.fillColor,
      defaultSelector: (context) => context.freeDrawDefaults.fillColor,
    ),
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.fillColor,
      defaultSelector: (context) => context.textDefaults.fillColor,
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.fillColor,
      defaultSelector: (context) => context.serialNumberDefaults.fillColor,
    ),
  ];

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.colorEquals);

  @override
  Color getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, Colors.transparent);
}

/// Property descriptor for fill style
class FillStylePropertyDescriptor extends PropertyDescriptor<FillStyle> {
  const FillStylePropertyDescriptor()
    : super(
        id: PropertyIds.fillStyle,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<FillStyle>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.fillStyle,
      defaultSelector: (context) => context.rectangleDefaults.fillStyle,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.fillStyle,
      defaultSelector: (context) => context.lineDefaults.fillStyle,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.fillStyle,
      defaultSelector: (context) => context.freeDrawDefaults.fillStyle,
    ),
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.fillStyle,
      defaultSelector: (context) => context.textDefaults.fillStyle,
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.fillStyle,
      defaultSelector: (context) => context.serialNumberDefaults.fillStyle,
    ),
  ];

  @override
  MixedValue<FillStyle> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.enumEquals);

  @override
  FillStyle getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, FillStyle.solid);
}

/// Property descriptor for opacity
class OpacityPropertyDescriptor extends PropertyDescriptor<double> {
  const OpacityPropertyDescriptor()
    : super(
        id: PropertyIds.opacity,
        supportedElementTypes: const {
          ElementType.rectangle,
          ElementType.highlight,
          ElementType.arrow,
          ElementType.line,
          ElementType.freeDraw,
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<double>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.opacity,
      defaultSelector: (context) => context.rectangleDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.highlight,
      valueSelector: (context) => context.highlightStyleValues.opacity,
      defaultSelector: (context) => context.highlightDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.arrow,
      valueSelector: (context) => context.arrowStyleValues.opacity,
      defaultSelector: (context) => context.arrowDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.line,
      valueSelector: (context) => context.lineStyleValues.opacity,
      defaultSelector: (context) => context.lineDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.freeDraw,
      valueSelector: (context) => context.freeDrawStyleValues.opacity,
      defaultSelector: (context) => context.freeDrawDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.opacity,
      defaultSelector: (context) => context.textDefaults.opacity,
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.opacity,
      defaultSelector: (context) => context.serialNumberDefaults.opacity,
    ),
  ];

  @override
  MixedValue<double> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.doubleEquals);

  @override
  double getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, 1);
}

/// Property descriptor for highlight mask color
class MaskColorPropertyDescriptor extends PropertyDescriptor<Color> {
  const MaskColorPropertyDescriptor()
    : super(
        id: PropertyIds.maskColor,
        supportedElementTypes: const {ElementType.highlight},
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.highlight)) {
      return MixedValue(value: context.highlightMask.maskColor, isMixed: false);
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) =>
      context.highlightMask.maskColor;
}

/// Property descriptor for highlight mask opacity
class MaskOpacityPropertyDescriptor extends PropertyDescriptor<double> {
  const MaskOpacityPropertyDescriptor()
    : super(
        id: PropertyIds.maskOpacity,
        supportedElementTypes: const {ElementType.highlight},
      );

  @override
  MixedValue<double> extractValue(StylePropertyContext context) {
    if (context.selectedElementTypes.contains(ElementType.highlight)) {
      return MixedValue(
        value: context.highlightMask.maskOpacity,
        isMixed: false,
      );
    }
    return const MixedValue(value: null, isMixed: true);
  }

  @override
  double getDefaultValue(StylePropertyContext context) =>
      context.highlightMask.maskOpacity;
}

/// Property descriptor for corner radius
class CornerRadiusPropertyDescriptor extends PropertyDescriptor<double> {
  const CornerRadiusPropertyDescriptor()
    : super(
        id: PropertyIds.cornerRadius,
        supportedElementTypes: const {ElementType.rectangle, ElementType.text},
      );

  static final List<_PropertySource<double>> _sources = [
    _PropertySource(
      elementType: ElementType.rectangle,
      valueSelector: (context) => context.rectangleStyleValues.cornerRadius,
      defaultSelector: (context) => context.rectangleDefaults.cornerRadius,
    ),
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.cornerRadius,
      defaultSelector: (context) => context.textDefaults.cornerRadius,
    ),
  ];

  @override
  MixedValue<double> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.doubleEquals);

  @override
  double getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, 0);
}

/// Property descriptor for font size
class FontSizePropertyDescriptor extends PropertyDescriptor<double> {
  const FontSizePropertyDescriptor()
    : super(
        id: PropertyIds.fontSize,
        supportedElementTypes: const {
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<double>> _sources = [
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.fontSize,
      defaultSelector: (context) => context.textDefaults.fontSize,
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.fontSize,
      defaultSelector: (context) => context.serialNumberDefaults.fontSize,
    ),
  ];

  @override
  MixedValue<double> extractValue(StylePropertyContext context) =>
      _extractMergedValue(context, _sources, PropertyUtils.doubleEquals);

  @override
  double getDefaultValue(StylePropertyContext context) =>
      _extractDefaultValue(context, _sources, context.textDefaults.fontSize);
}

/// Property descriptor for font family
class FontFamilyPropertyDescriptor extends PropertyDescriptor<String> {
  const FontFamilyPropertyDescriptor()
    : super(
        id: PropertyIds.fontFamily,
        supportedElementTypes: const {
          ElementType.text,
          ElementType.serialNumber,
        },
      );

  static final List<_PropertySource<String>> _sources = [
    _PropertySource(
      elementType: ElementType.text,
      valueSelector: (context) => context.textStyleValues.fontFamily,
      defaultSelector: (context) => context.textDefaults.fontFamily ?? '',
    ),
    _PropertySource(
      elementType: ElementType.serialNumber,
      valueSelector: (context) => context.serialNumberStyleValues.fontFamily,
      defaultSelector: (context) =>
          context.serialNumberDefaults.fontFamily ?? '',
    ),
  ];

  @override
  MixedValue<String> extractValue(StylePropertyContext context) =>
      _extractMergedValue(
        context,
        _sources,
        PropertyUtils.stringEquals,
        treatNullAsValue: true,
      );

  @override
  String getDefaultValue(StylePropertyContext context) => _extractDefaultValue(
    context,
    _sources,
    context.textDefaults.fontFamily ?? '',
  );
}

/// Property descriptor for serial number value
class SerialNumberPropertyDescriptor extends PropertyDescriptor<int> {
  const SerialNumberPropertyDescriptor()
    : super(
        id: PropertyIds.serialNumber,
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
    : super(
        id: PropertyIds.textAlign,
        supportedElementTypes: const {ElementType.text},
      );

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

/// Property descriptor for start arrowhead style
class StartArrowheadPropertyDescriptor
    extends PropertyDescriptor<ArrowheadStyle> {
  const StartArrowheadPropertyDescriptor()
    : super(
        id: PropertyIds.startArrowhead,
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
        id: PropertyIds.endArrowhead,
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
    : super(
        id: PropertyIds.arrowType,
        supportedElementTypes: const {ElementType.arrow},
      );

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
        id: PropertyIds.textStrokeColor,
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
        id: PropertyIds.textStrokeWidth,
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
