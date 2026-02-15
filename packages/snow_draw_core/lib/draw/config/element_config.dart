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
  }) {
    final nextMinValidSize = minValidSize ?? this.minValidSize;
    final nextMinCreateSize = minCreateSize ?? this.minCreateSize;
    final nextMinResizeSize = minResizeSize ?? this.minResizeSize;
    final nextRotationSnapAngle = rotationSnapAngle ?? this.rotationSnapAngle;
    if (nextMinValidSize == this.minValidSize &&
        nextMinCreateSize == this.minCreateSize &&
        nextMinResizeSize == this.minResizeSize &&
        nextRotationSnapAngle == this.rotationSnapAngle) {
      return this;
    }
    return ElementConfig(
      minValidSize: nextMinValidSize,
      minCreateSize: nextMinCreateSize,
      minResizeSize: nextMinResizeSize,
      rotationSnapAngle: nextRotationSnapAngle,
    );
  }

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
  static const _fontFamilyUnchanged = Object();

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
    this.filterType = ConfigDefaults.defaultFilterType,
    this.filterStrength = ConfigDefaults.defaultFilterStrength,
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
       assert(filterStrength >= 0, 'filterStrength must be non-negative'),
       assert(filterStrength <= 1, 'filterStrength must be <= 1'),
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

  /// Default filter type for filter elements.
  final CanvasFilterType filterType;

  /// Default filter strength for filter elements.
  final double filterStrength;

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
    CanvasFilterType? filterType,
    double? filterStrength,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    Object? fontFamily = _fontFamilyUnchanged,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    Color? textStrokeColor,
    double? textStrokeWidth,
  }) {
    final nextOpacity = opacity ?? this.opacity;
    final nextZIndex = zIndex ?? this.zIndex;
    final nextSerialNumber = serialNumber ?? this.serialNumber;
    final nextStrokeWidth = strokeWidth ?? this.strokeWidth;
    final nextColor = color ?? this.color;
    final nextFillColor = fillColor ?? this.fillColor;
    final nextStrokeStyle = strokeStyle ?? this.strokeStyle;
    final nextFillStyle = fillStyle ?? this.fillStyle;
    final nextHighlightShape = highlightShape ?? this.highlightShape;
    final nextFilterType = filterType ?? this.filterType;
    final nextFilterStrength = filterStrength ?? this.filterStrength;
    final nextCornerRadius = cornerRadius ?? this.cornerRadius;
    final nextArrowType = arrowType ?? this.arrowType;
    final nextStartArrowhead = startArrowhead ?? this.startArrowhead;
    final nextEndArrowhead = endArrowhead ?? this.endArrowhead;
    final nextFontSize = fontSize ?? this.fontSize;
    // Sentinel-based detection keeps nullable semantics: omitted keeps current,
    // while an explicit `fontFamily: null` clears the override.
    if (!identical(fontFamily, _fontFamilyUnchanged) &&
        fontFamily is! String?) {
      throw ArgumentError.value(
        fontFamily,
        'fontFamily',
        'must be a String, null, or omitted',
      );
    }
    final nextFontFamily = identical(fontFamily, _fontFamilyUnchanged)
        ? this.fontFamily
        : _normalizeFontFamily(fontFamily as String?);
    final nextTextAlign = textAlign ?? this.textAlign;
    final nextVerticalAlign = verticalAlign ?? this.verticalAlign;
    final nextTextStrokeColor = textStrokeColor ?? this.textStrokeColor;
    final nextTextStrokeWidth = textStrokeWidth ?? this.textStrokeWidth;

    if (nextOpacity == this.opacity &&
        nextZIndex == this.zIndex &&
        nextSerialNumber == this.serialNumber &&
        nextStrokeWidth == this.strokeWidth &&
        nextColor == this.color &&
        nextFillColor == this.fillColor &&
        nextStrokeStyle == this.strokeStyle &&
        nextFillStyle == this.fillStyle &&
        nextHighlightShape == this.highlightShape &&
        nextFilterType == this.filterType &&
        nextFilterStrength == this.filterStrength &&
        nextCornerRadius == this.cornerRadius &&
        nextArrowType == this.arrowType &&
        nextStartArrowhead == this.startArrowhead &&
        nextEndArrowhead == this.endArrowhead &&
        nextFontSize == this.fontSize &&
        nextFontFamily == this.fontFamily &&
        nextTextAlign == this.textAlign &&
        nextVerticalAlign == this.verticalAlign &&
        nextTextStrokeColor == this.textStrokeColor &&
        nextTextStrokeWidth == this.textStrokeWidth) {
      return this;
    }

    return ElementStyleConfig(
      opacity: nextOpacity,
      zIndex: nextZIndex,
      serialNumber: nextSerialNumber,
      strokeWidth: nextStrokeWidth,
      color: nextColor,
      fillColor: nextFillColor,
      strokeStyle: nextStrokeStyle,
      fillStyle: nextFillStyle,
      highlightShape: nextHighlightShape,
      filterType: nextFilterType,
      filterStrength: nextFilterStrength,
      cornerRadius: nextCornerRadius,
      arrowType: nextArrowType,
      startArrowhead: nextStartArrowhead,
      endArrowhead: nextEndArrowhead,
      fontSize: nextFontSize,
      fontFamily: nextFontFamily,
      textAlign: nextTextAlign,
      verticalAlign: nextVerticalAlign,
      textStrokeColor: nextTextStrokeColor,
      textStrokeWidth: nextTextStrokeWidth,
    );
  }

  static String? _normalizeFontFamily(String? fontFamily) {
    if (fontFamily == null) {
      return null;
    }
    return fontFamily.trim().isEmpty ? null : fontFamily;
  }

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
          other.filterType == filterType &&
          other.filterStrength == filterStrength &&
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
  int get hashCode => Object.hashAll([
    opacity,
    zIndex,
    serialNumber,
    strokeWidth,
    color,
    fillColor,
    strokeStyle,
    fillStyle,
    highlightShape,
    filterType,
    filterStrength,
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
  ]);

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
      'filterType: $filterType, '
      'filterStrength: $filterStrength, '
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
