part of 'draw_config.dart';

/// Canvas-level configuration.
@immutable
class CanvasConfig {
  const CanvasConfig({this.backgroundColor = ConfigDefaults.backgroundColor});

  /// Background color of the canvas.
  final DrawColor backgroundColor;

  CanvasConfig copyWith({DrawColor? backgroundColor}) {
    if (backgroundColor == null || backgroundColor == this.backgroundColor) {
      return this;
    }
    return CanvasConfig(backgroundColor: backgroundColor);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasConfig && other.backgroundColor == backgroundColor;

  @override
  int get hashCode => backgroundColor.hashCode;

  @override
  String toString() => 'CanvasConfig(backgroundColor: $backgroundColor)';
}

/// Configuration for box selection (marquee selection).
@immutable
class BoxSelectionConfig {
  const BoxSelectionConfig({
    this.fillColor = ConfigDefaults.accentColor,
    this.fillOpacity = ConfigDefaults.boxSelectionFillOpacity,
    this.strokeColor = ConfigDefaults.accentColor,
    this.strokeWidth = ConfigDefaults.selectionStrokeWidth,
  }) : assert(
         fillOpacity >= 0 && fillOpacity <= 1,
         'fillOpacity must be in [0, 1]',
       ),
       assert(strokeWidth >= 0, 'strokeWidth must be non-negative');

  /// Fill color of the selection box.
  final DrawColor fillColor;

  /// Opacity of the fill (0.0 to 1.0).
  final double fillOpacity;

  /// Stroke color of the selection box border.
  final DrawColor strokeColor;

  /// Stroke width of the selection box border.
  final double strokeWidth;

  BoxSelectionConfig copyWith({
    DrawColor? fillColor,
    double? fillOpacity,
    DrawColor? strokeColor,
    double? strokeWidth,
  }) {
    if ((fillColor == null || fillColor == this.fillColor) &&
        (fillOpacity == null || fillOpacity == this.fillOpacity) &&
        (strokeColor == null || strokeColor == this.strokeColor) &&
        (strokeWidth == null || strokeWidth == this.strokeWidth)) {
      return this;
    }
    return BoxSelectionConfig(
      fillColor: fillColor ?? this.fillColor,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxSelectionConfig &&
          other.fillColor == fillColor &&
          other.fillOpacity == fillOpacity &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(fillColor, fillOpacity, strokeColor, strokeWidth);

  @override
  String toString() =>
      'BoxSelectionConfig('
      'fillColor: $fillColor, '
      'fillOpacity: $fillOpacity, '
      'strokeColor: $strokeColor, '
      'strokeWidth: $strokeWidth'
      ')';
}
