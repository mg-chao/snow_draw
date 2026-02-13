import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:meta/meta.dart';

import '../types/element_style.dart';

part 'selection_config.dart';
part 'element_config.dart';
part 'canvas_config.dart';
part 'grid_config.dart';
part 'snap_config.dart';
part 'highlight_config.dart';

/// Centralized default values for the configuration system.
///
/// Keep defaults consistent across config classes and make theme changes
/// easier.
abstract class ConfigDefaults {
  ConfigDefaults._();

  // ===== Colors =====
  /// Primary accent color (selection outline, etc.).
  static const primaryColor = Color(0xFF1677FF);

  /// Secondary accent color (box selection, etc.).
  static const accentColor = Color(0xFF4096FF);

  /// Canvas background color.
  static const backgroundColor = Color(0xFFFFFFFF);

  /// Default element color.
  static const defaultColor = Color(0xFF1E1E1E);

  /// Default element fill color.
  static const defaultFillColor = Color(0x00000000);

  /// Default highlight fill color.
  static const defaultHighlightColor = Color(0xFFF5222D);

  /// Default highlight stroke color.
  static const defaultHighlightStrokeColor = Color(0xFF000000);

  /// Default highlight shape.
  static const HighlightShape defaultHighlightShape = HighlightShape.rectangle;

  /// Default canvas filter type.
  static const CanvasFilterType defaultFilterType = CanvasFilterType.mosaic;

  /// Default canvas filter strength.
  static const defaultFilterStrength = 0.5;

  /// Default mask color.
  static const defaultMaskColor = Color(0xFF000000);

  /// Default element corner radius.
  static const defaultCornerRadius = 4.0;

  /// Default element stroke style.
  static const StrokeStyle defaultStrokeStyle = StrokeStyle.solid;

  /// Default element fill style.
  static const FillStyle defaultFillStyle = FillStyle.solid;

  // ===== Arrow =====
  static const ArrowType defaultArrowType = ArrowType.straight;
  static const ArrowheadStyle defaultStartArrowhead = ArrowheadStyle.none;
  static const ArrowheadStyle defaultEndArrowhead = ArrowheadStyle.standard;

  // ===== Text =====
  static const defaultTextFontSize = 21.0;
  static const defaultSerialNumberFontSize = 16.0;
  static const String? defaultTextFontFamily = null;
  static const defaultTextStrokeColor = Color(0xFFF8F4EC);
  static const defaultTextStrokeWidth = 0.0;
  static const defaultTextCornerRadius = 0.0;
  static const defaultSerialNumber = 1;
  static const TextHorizontalAlign defaultTextHorizontalAlign =
      TextHorizontalAlign.left;
  static const TextVerticalAlign defaultTextVerticalAlign =
      TextVerticalAlign.center;
  static const defaultTextAutoResize = true;
  static const textMinWidth = 24.0;
  static const textMaxAutoWidth = 240.0;

  /// Control point fill color.
  static const controlPointFillColor = Color(0xFFFFFFFF);

  // ===== Sizes =====
  static const defaultStrokeWidth = 2.0;
  static const controlPointSize = 8.0;
  static const controlPointRadius = 2.0;

  /// Multiplier for arrow point editor control points
  /// (makes them larger than standard control points)
  static const arrowPointSizeMultiplier = 1.25;

  static const selectionPadding = 3.0;
  static const selectionStrokeWidth = 1.0;
  static const rotateHandleOffset = 12.0;

  // ===== Interaction =====
  static const handleTolerance = 6.0;
  static const freeDrawCloseToleranceMultiplier = 1.5;
  static const dragThreshold = 0.0;

  // ===== Elements =====
  static const minValidElementSize = 5.0;
  static const minCreateElementSize = 8.0;
  static const double minResizeElementSize = minValidElementSize;

  static const defaultOpacity = 1.0;
  static const boxSelectionFillOpacity = 0.2;

  /// Rotation snap angle interval in radians (15 degrees).
  ///
  /// Use `0.0` to disable snapping when discrete rotation is enabled.
  static const double rotationSnapAngle = math.pi / 12;

  // ===== Object Snapping =====
  static const objectSnapEnabled = false;
  static const double objectSnapDistance = 8;
  static const objectSnapPointEnabled = true;
  static const objectSnapGapEnabled = true;
  static const objectSnapShowGuides = true;
  static const objectSnapShowGapSize = false;
  static const objectSnapLineColor = Color(0xFFFF6B6B);
  static const double objectSnapLineWidth = 1;
  static const double objectSnapMarkerSize = 8;
  static const double objectSnapGapDashLength = 4;
  static const double objectSnapGapDashGap = 4;
  static const arrowBindingEnabled = true;
  static const double arrowBindingDistance = 10;

  // ===== Grid =====
  static const gridEnabled = false;
  static const gridSize = 20.0;
  static const gridMinSize = 5.0;
  static const gridMaxSize = 100.0;
  static const gridSizePresets = [10.0, 20.0, 40.0, 80.0];
  static const gridLineColor = Color(0xFFBDBDBD);
  static const gridLineOpacity = 0.45;
  static const gridMajorLineOpacity = 0.7;
  static const gridLineWidth = 1.0;
  static const gridMajorLineEvery = 5;
  static const gridMinScreenSpacing = 10.0;
  static const gridMinRenderSpacing = 2.0;
}

/// Top-level draw configuration.
@immutable
class DrawConfig {
  DrawConfig({
    this.selection = const SelectionConfig(),
    this.element = const ElementConfig(),
    this.canvas = const CanvasConfig(),
    this.boxSelection = const BoxSelectionConfig(),
    this.elementStyle = const ElementStyleConfig(),
    ElementStyleConfig? rectangleStyle,
    ElementStyleConfig? arrowStyle,
    ElementStyleConfig? lineStyle,
    ElementStyleConfig? freeDrawStyle,
    ElementStyleConfig? textStyle,
    ElementStyleConfig? serialNumberStyle,
    ElementStyleConfig? filterStyle,
    ElementStyleConfig? highlightStyle,
    HighlightMaskConfig? highlight,
    this.grid = const GridConfig(),
    this.snap = const SnapConfig(),
  }) : rectangleStyle = rectangleStyle ?? elementStyle,
       arrowStyle = arrowStyle ?? elementStyle,
       lineStyle = lineStyle ?? elementStyle,
       freeDrawStyle = freeDrawStyle ?? elementStyle,
       textStyle = textStyle ?? elementStyle,
       serialNumberStyle =
           serialNumberStyle ?? _deriveSerialNumberStyle(elementStyle),
       filterStyle = filterStyle ?? _deriveFilterStyle(elementStyle),
       highlightStyle = highlightStyle ?? _deriveHighlightStyle(elementStyle),
       highlight = highlight ?? const HighlightMaskConfig();
  final SelectionConfig selection;
  final ElementConfig element;
  final CanvasConfig canvas;
  final BoxSelectionConfig boxSelection;
  final ElementStyleConfig elementStyle;
  final ElementStyleConfig rectangleStyle;
  final ElementStyleConfig arrowStyle;
  final ElementStyleConfig lineStyle;
  final ElementStyleConfig freeDrawStyle;
  final ElementStyleConfig textStyle;
  final ElementStyleConfig serialNumberStyle;
  final ElementStyleConfig filterStyle;
  final ElementStyleConfig highlightStyle;
  final HighlightMaskConfig highlight;
  final GridConfig grid;
  final SnapConfig snap;

  static final defaultConfig = DrawConfig();

  DrawConfig copyWith({
    SelectionConfig? selection,
    ElementConfig? element,
    CanvasConfig? canvas,
    BoxSelectionConfig? boxSelection,
    ElementStyleConfig? elementStyle,
    ElementStyleConfig? rectangleStyle,
    ElementStyleConfig? arrowStyle,
    ElementStyleConfig? lineStyle,
    ElementStyleConfig? freeDrawStyle,
    ElementStyleConfig? textStyle,
    ElementStyleConfig? serialNumberStyle,
    ElementStyleConfig? filterStyle,
    ElementStyleConfig? highlightStyle,
    HighlightMaskConfig? highlight,
    GridConfig? grid,
    SnapConfig? snap,
  }) {
    final nextElementStyle = elementStyle ?? this.elementStyle;
    final nextHighlightStyle = _deriveHighlightStyle(nextElementStyle);
    final nextFilterStyle = _deriveFilterStyle(nextElementStyle);
    final nextSerialNumberStyle = _deriveSerialNumberStyle(
      nextElementStyle,
      serialNumber: this.serialNumberStyle.serialNumber,
    );
    return DrawConfig(
      selection: selection ?? this.selection,
      element: element ?? this.element,
      canvas: canvas ?? this.canvas,
      boxSelection: boxSelection ?? this.boxSelection,
      elementStyle: nextElementStyle,
      rectangleStyle:
          rectangleStyle ??
          (elementStyle != null ? nextElementStyle : this.rectangleStyle),
      arrowStyle:
          arrowStyle ??
          (elementStyle != null ? nextElementStyle : this.arrowStyle),
      lineStyle:
          lineStyle ??
          (elementStyle != null ? nextElementStyle : this.lineStyle),
      freeDrawStyle:
          freeDrawStyle ??
          (elementStyle != null ? nextElementStyle : this.freeDrawStyle),
      textStyle:
          textStyle ??
          (elementStyle != null ? nextElementStyle : this.textStyle),
      serialNumberStyle:
          serialNumberStyle ??
          (elementStyle != null
              ? nextSerialNumberStyle
              : this.serialNumberStyle),
      filterStyle:
          filterStyle ??
          (elementStyle != null ? nextFilterStyle : this.filterStyle),
      highlightStyle:
          highlightStyle ??
          (elementStyle != null ? nextHighlightStyle : this.highlightStyle),
      highlight: highlight ?? this.highlight,
      grid: grid ?? this.grid,
      snap: snap ?? this.snap,
    );
  }

  static ElementStyleConfig _deriveSerialNumberStyle(
    ElementStyleConfig elementStyle, {
    int? serialNumber,
  }) => elementStyle.copyWith(
    serialNumber: serialNumber ?? elementStyle.serialNumber,
    fontSize: ConfigDefaults.defaultSerialNumberFontSize,
  );

  static ElementStyleConfig _deriveFilterStyle(
    ElementStyleConfig elementStyle,
  ) => elementStyle.copyWith(
    filterType: ConfigDefaults.defaultFilterType,
    filterStrength: ConfigDefaults.defaultFilterStrength,
  );

  static ElementStyleConfig _deriveHighlightStyle(
    ElementStyleConfig elementStyle,
  ) => elementStyle.copyWith(
    color: ConfigDefaults.defaultHighlightColor,
    textStrokeColor: ConfigDefaults.defaultHighlightStrokeColor,
    textStrokeWidth: 0,
    highlightShape: ConfigDefaults.defaultHighlightShape,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawConfig &&
          other.selection == selection &&
          other.element == element &&
          other.canvas == canvas &&
          other.boxSelection == boxSelection &&
          other.elementStyle == elementStyle &&
          other.rectangleStyle == rectangleStyle &&
          other.arrowStyle == arrowStyle &&
          other.lineStyle == lineStyle &&
          other.freeDrawStyle == freeDrawStyle &&
          other.textStyle == textStyle &&
          other.serialNumberStyle == serialNumberStyle &&
          other.filterStyle == filterStyle &&
          other.highlightStyle == highlightStyle &&
          other.highlight == highlight &&
          other.grid == grid &&
          other.snap == snap;

  @override
  int get hashCode => Object.hash(
    selection,
    element,
    canvas,
    boxSelection,
    elementStyle,
    rectangleStyle,
    arrowStyle,
    lineStyle,
    freeDrawStyle,
    textStyle,
    serialNumberStyle,
    filterStyle,
    highlightStyle,
    highlight,
    grid,
    snap,
  );

  @override
  String toString() =>
      'DrawConfig('
      'selection: $selection, '
      'element: $element, '
      'canvas: $canvas, '
      'boxSelection: $boxSelection, '
      'elementStyle: $elementStyle, '
      'rectangleStyle: $rectangleStyle, '
      'arrowStyle: $arrowStyle, '
      'lineStyle: $lineStyle, '
      'freeDrawStyle: $freeDrawStyle, '
      'textStyle: $textStyle, '
      'serialNumberStyle: $serialNumberStyle, '
      'filterStyle: $filterStyle, '
      'highlightStyle: $highlightStyle, '
      'highlight: $highlight, '
      'grid: $grid, '
      'snap: $snap'
      ')';
}
