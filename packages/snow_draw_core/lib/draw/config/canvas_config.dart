part of 'draw_config.dart';

/// Canvas-level configuration.
@immutable
class CanvasConfig {
  const CanvasConfig({this.backgroundColor = ConfigDefaults.backgroundColor});

  /// Background color of the canvas.
  final Color backgroundColor;

  CanvasConfig copyWith({Color? backgroundColor}) {
    final nextBackgroundColor = backgroundColor ?? this.backgroundColor;
    if (nextBackgroundColor == this.backgroundColor) {
      return this;
    }
    return CanvasConfig(backgroundColor: nextBackgroundColor);
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
  final Color fillColor;

  /// Opacity of the fill (0.0 to 1.0).
  final double fillOpacity;

  /// Stroke color of the selection box border.
  final Color strokeColor;

  /// Stroke width of the selection box border.
  final double strokeWidth;

  BoxSelectionConfig copyWith({
    Color? fillColor,
    double? fillOpacity,
    Color? strokeColor,
    double? strokeWidth,
  }) {
    final nextFillColor = fillColor ?? this.fillColor;
    final nextFillOpacity = fillOpacity ?? this.fillOpacity;
    final nextStrokeColor = strokeColor ?? this.strokeColor;
    final nextStrokeWidth = strokeWidth ?? this.strokeWidth;
    if (nextFillColor == this.fillColor &&
        nextFillOpacity == this.fillOpacity &&
        nextStrokeColor == this.strokeColor &&
        nextStrokeWidth == this.strokeWidth) {
      return this;
    }
    return BoxSelectionConfig(
      fillColor: nextFillColor,
      fillOpacity: nextFillOpacity,
      strokeColor: nextStrokeColor,
      strokeWidth: nextStrokeWidth,
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
