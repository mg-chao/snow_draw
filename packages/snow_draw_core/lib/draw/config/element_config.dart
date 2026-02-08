part of 'draw_config.dart';

/// Element configuration.
@immutable
class ElementConfig {
  const ElementConfig({
    this.minValidSize = ConfigDefaults.minValidElementSize,
    this.minCreateSize = ConfigDefaults.minCreateElementSize,
    this.minResizeSize = ConfigDefaults.minResizeElementSize,
    this.rotationSnapAngle = ConfigDefaults.rotationSnapAngle,
  }) : assert(minValidSize > 0, 'minValidSize must be positive'),
       assert(minCreateSize > 0, 'minCreateSize must be positive'),
       assert(
         minCreateSize >= minValidSize,
         'minCreateSize must be >= minValidSize',
       ),
       assert(minResizeSize > 0, 'minResizeSize must be positive'),
       assert(
         minResizeSize >= minValidSize,
         'minResizeSize must be >= minValidSize',
       ),
       assert(rotationSnapAngle >= 0, 'rotationSnapAngle must be non-negative');

  /// Elements smaller than this value will be treated as invalid and removed.
  final double minValidSize;

  /// Minimum size to start creating an element (UI may use this for feedback).
  final double minCreateSize;

  /// Minimum size allowed during resize interactions.
  ///
  /// This helps prevent users from resizing elements into an unusable size.
  final double minResizeSize;

  /// Rotation snap angle interval in radians.
  ///
  /// Use `0.0` to disable snapping when discrete rotation is enabled.
  final double rotationSnapAngle;

  ElementConfig copyWith({
    double? minValidSize,
    double? minCreateSize,
    double? minResizeSize,
    double? rotationSnapAngle,
  }) => ElementConfig(
    minValidSize: minValidSize ?? this.minValidSize,
    minCreateSize: minCreateSize ?? this.minCreateSize,
    minResizeSize: minResizeSize ?? this.minResizeSize,
    rotationSnapAngle: rotationSnapAngle ?? this.rotationSnapAngle,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementConfig &&
          other.minValidSize == minValidSize &&
          other.minCreateSize == minCreateSize &&
          other.minResizeSize == minResizeSize &&
          other.rotationSnapAngle == rotationSnapAngle;

  @override
  int get hashCode => Object.hash(
    minValidSize,
    minCreateSize,
    minResizeSize,
    rotationSnapAngle,
  );

  @override
  String toString() =>
      'ElementConfig('
      'minValidSize: $minValidSize, '
      'minCreateSize: $minCreateSize, '
      'minResizeSize: $minResizeSize, '
      'rotationSnapAngle: $rotationSnapAngle'
      ')';
}

/// Default element style configuration.
@immutable
class ElementStyleConfig {
  const ElementStyleConfig({
    this.opacity = ConfigDefaults.defaultOpacity,
    this.zIndex = 1,
    this.serialNumber = ConfigDefaults.defaultSerialNumber,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.color = ConfigDefaults.defaultColor,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
    this.highlightShape = ConfigDefaults.defaultHighlightShape,
    this.cornerRadius = ConfigDefaults.defaultCornerRadius,
    this.arrowType = ConfigDefaults.defaultArrowType,
    this.startArrowhead = ConfigDefaults.defaultStartArrowhead,
    this.endArrowhead = ConfigDefaults.defaultEndArrowhead,
    this.fontSize = ConfigDefaults.defaultTextFontSize,
    this.fontFamily = ConfigDefaults.defaultTextFontFamily,
    this.textAlign = ConfigDefaults.defaultTextHorizontalAlign,
    this.verticalAlign = ConfigDefaults.defaultTextVerticalAlign,
    this.textStrokeColor = ConfigDefaults.defaultTextStrokeColor,
    this.textStrokeWidth = ConfigDefaults.defaultTextStrokeWidth,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be in [0, 1]'),
       assert(zIndex >= 0, 'zIndex must be non-negative'),
       assert(serialNumber >= 0, 'serialNumber must be non-negative'),
       assert(strokeWidth >= 0, 'strokeWidth must be non-negative'),
       assert(cornerRadius >= 0, 'cornerRadius must be non-negative'),
       assert(fontSize >= 0, 'fontSize must be non-negative'),
       assert(textStrokeWidth >= 0, 'textStrokeWidth must be non-negative');

  /// Default opacity of newly created elements.
  final double opacity;

  /// Default z-index for newly created elements.
  ///
  /// Note: the runtime may still enforce its own z-indexing strategy to keep
  /// layer ordering stable.
  final int zIndex;

  /// Default serial number value for serial number elements.
  final int serialNumber;

  /// Default stroke width used by element types that support strokes.
  final double strokeWidth;

  /// Default color used by element types that support a primary color.
  final Color color;

  /// Default fill color used by element types that support fills.
  final Color fillColor;

  /// Default stroke style used by element types that support strokes.
  final StrokeStyle strokeStyle;

  /// Default fill style used by element types that support fills.
  final FillStyle fillStyle;

  /// Default highlight shape for highlight elements.
  final HighlightShape highlightShape;

  /// Default corner radius for supported elements.
  final double cornerRadius;

  /// Default arrow type for arrow elements.
  final ArrowType arrowType;

  /// Default start arrowhead style for arrow elements.
  final ArrowheadStyle startArrowhead;

  /// Default end arrowhead style for arrow elements.
  final ArrowheadStyle endArrowhead;

  /// Default font size for text elements.
  final double fontSize;

  /// Default font family for text elements (null uses system default).
  final String? fontFamily;

  /// Default horizontal alignment for text elements.
  final TextHorizontalAlign textAlign;

  /// Default vertical alignment for text elements.
  final TextVerticalAlign verticalAlign;

  /// Default text stroke color for text elements.
  final Color textStrokeColor;

  /// Default text stroke width for text elements.
  final double textStrokeWidth;

  ElementStyleConfig copyWith({
    double? opacity,
    int? zIndex,
    int? serialNumber,
    double? strokeWidth,
    Color? color,
    Color? fillColor,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
    HighlightShape? highlightShape,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    String? fontFamily,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    Color? textStrokeColor,
    double? textStrokeWidth,
  }) => ElementStyleConfig(
    opacity: opacity ?? this.opacity,
    zIndex: zIndex ?? this.zIndex,
    serialNumber: serialNumber ?? this.serialNumber,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    color: color ?? this.color,
    fillColor: fillColor ?? this.fillColor,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    fillStyle: fillStyle ?? this.fillStyle,
    highlightShape: highlightShape ?? this.highlightShape,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    arrowType: arrowType ?? this.arrowType,
    startArrowhead: startArrowhead ?? this.startArrowhead,
    endArrowhead: endArrowhead ?? this.endArrowhead,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily == null
        ? this.fontFamily
        : (fontFamily.trim().isEmpty ? null : fontFamily),
    textAlign: textAlign ?? this.textAlign,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    textStrokeColor: textStrokeColor ?? this.textStrokeColor,
    textStrokeWidth: textStrokeWidth ?? this.textStrokeWidth,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementStyleConfig &&
          other.opacity == opacity &&
          other.zIndex == zIndex &&
          other.serialNumber == serialNumber &&
          other.strokeWidth == strokeWidth &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.strokeStyle == strokeStyle &&
          other.fillStyle == fillStyle &&
          other.highlightShape == highlightShape &&
          other.cornerRadius == cornerRadius &&
          other.arrowType == arrowType &&
          other.startArrowhead == startArrowhead &&
          other.endArrowhead == endArrowhead &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.textAlign == textAlign &&
          other.verticalAlign == verticalAlign &&
          other.textStrokeColor == textStrokeColor &&
          other.textStrokeWidth == textStrokeWidth;

  @override
  int get hashCode => Object.hash(
    opacity,
    zIndex,
    serialNumber,
    strokeWidth,
    color,
    fillColor,
    strokeStyle,
    fillStyle,
    highlightShape,
    cornerRadius,
    arrowType,
    startArrowhead,
    endArrowhead,
    fontSize,
    fontFamily,
    textAlign,
    verticalAlign,
    textStrokeColor,
    textStrokeWidth,
  );

  @override
  String toString() =>
      'ElementStyleConfig('
      'opacity: $opacity, '
      'zIndex: $zIndex, '
      'serialNumber: $serialNumber, '
      'strokeWidth: $strokeWidth, '
      'color: $color, '
      'fillColor: $fillColor, '
      'strokeStyle: $strokeStyle, '
      'fillStyle: $fillStyle, '
      'highlightShape: $highlightShape, '
      'cornerRadius: $cornerRadius, '
      'arrowType: $arrowType, '
      'startArrowhead: $startArrowhead, '
      'endArrowhead: $endArrowhead, '
      'fontSize: $fontSize, '
      'fontFamily: $fontFamily, '
      'textAlign: $textAlign, '
      'verticalAlign: $verticalAlign, '
      'textStrokeColor: $textStrokeColor, '
      'textStrokeWidth: $textStrokeWidth'
      ')';
}
