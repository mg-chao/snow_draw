part of 'draw_config.dart';

/// Grid snapping and rendering configuration.
@immutable
class GridConfig {
  const GridConfig({
    this.enabled = ConfigDefaults.gridEnabled,
    this.size = ConfigDefaults.gridSize,
    this.lineColor = ConfigDefaults.gridLineColor,
    this.lineOpacity = ConfigDefaults.gridLineOpacity,
    this.majorLineOpacity = ConfigDefaults.gridMajorLineOpacity,
    this.lineWidth = ConfigDefaults.gridLineWidth,
    this.majorLineEvery = ConfigDefaults.gridMajorLineEvery,
    this.minScreenSpacing = ConfigDefaults.gridMinScreenSpacing,
    this.minRenderSpacing = ConfigDefaults.gridMinRenderSpacing,
  }) : assert(size >= ConfigDefaults.gridMinSize, 'size too small'),
       assert(size <= ConfigDefaults.gridMaxSize, 'size too large'),
       assert(lineOpacity >= 0 && lineOpacity <= 1, 'lineOpacity in [0, 1]'),
       assert(
         majorLineOpacity >= 0 && majorLineOpacity <= 1,
         'majorLineOpacity in [0, 1]',
       ),
       assert(lineWidth > 0, 'lineWidth must be positive'),
       assert(majorLineEvery > 0, 'majorLineEvery must be positive'),
       assert(minScreenSpacing > 0, 'minScreenSpacing must be positive'),
       assert(minRenderSpacing >= 0, 'minRenderSpacing must be non-negative'),
       assert(
         minRenderSpacing <= minScreenSpacing,
         'minRenderSpacing must be <= minScreenSpacing',
       );

  /// Whether grid snapping and rendering is enabled.
  final bool enabled;

  /// Grid cell size in world pixels.
  final double size;

  /// Base color for grid lines.
  final Color lineColor;

  /// Opacity for minor grid lines.
  final double lineOpacity;

  /// Opacity for major grid lines.
  final double majorLineOpacity;

  /// Line width in screen pixels.
  final double lineWidth;

  /// Number of minor cells between major lines.
  final int majorLineEvery;

  /// Minimum screen spacing (px) between rendered grid lines.
  final double minScreenSpacing;

  /// Hide grid if base spacing falls below this (px).
  final double minRenderSpacing;

  static const double minSize = ConfigDefaults.gridMinSize;
  static const double maxSize = ConfigDefaults.gridMaxSize;
  static const List<double> presetSizes = ConfigDefaults.gridSizePresets;

  GridConfig copyWith({
    bool? enabled,
    double? size,
    Color? lineColor,
    double? lineOpacity,
    double? majorLineOpacity,
    double? lineWidth,
    int? majorLineEvery,
    double? minScreenSpacing,
    double? minRenderSpacing,
  }) {
    final nextEnabled = enabled ?? this.enabled;
    final nextSize = size ?? this.size;
    final nextLineColor = lineColor ?? this.lineColor;
    final nextLineOpacity = lineOpacity ?? this.lineOpacity;
    final nextMajorLineOpacity = majorLineOpacity ?? this.majorLineOpacity;
    final nextLineWidth = lineWidth ?? this.lineWidth;
    final nextMajorLineEvery = majorLineEvery ?? this.majorLineEvery;
    final nextMinScreenSpacing = minScreenSpacing ?? this.minScreenSpacing;
    final nextMinRenderSpacing = minRenderSpacing ?? this.minRenderSpacing;
    if (nextEnabled == this.enabled &&
        nextSize == this.size &&
        nextLineColor == this.lineColor &&
        nextLineOpacity == this.lineOpacity &&
        nextMajorLineOpacity == this.majorLineOpacity &&
        nextLineWidth == this.lineWidth &&
        nextMajorLineEvery == this.majorLineEvery &&
        nextMinScreenSpacing == this.minScreenSpacing &&
        nextMinRenderSpacing == this.minRenderSpacing) {
      return this;
    }
    return GridConfig(
      enabled: nextEnabled,
      size: nextSize,
      lineColor: nextLineColor,
      lineOpacity: nextLineOpacity,
      majorLineOpacity: nextMajorLineOpacity,
      lineWidth: nextLineWidth,
      majorLineEvery: nextMajorLineEvery,
      minScreenSpacing: nextMinScreenSpacing,
      minRenderSpacing: nextMinRenderSpacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridConfig &&
          other.enabled == enabled &&
          other.size == size &&
          other.lineColor == lineColor &&
          other.lineOpacity == lineOpacity &&
          other.majorLineOpacity == majorLineOpacity &&
          other.lineWidth == lineWidth &&
          other.majorLineEvery == majorLineEvery &&
          other.minScreenSpacing == minScreenSpacing &&
          other.minRenderSpacing == minRenderSpacing;

  @override
  int get hashCode => Object.hash(
    enabled,
    size,
    lineColor,
    lineOpacity,
    majorLineOpacity,
    lineWidth,
    majorLineEvery,
    minScreenSpacing,
    minRenderSpacing,
  );

  @override
  String toString() =>
      'GridConfig('
      'enabled: $enabled, '
      'size: $size, '
      'lineColor: $lineColor, '
      'lineOpacity: $lineOpacity, '
      'majorLineOpacity: $majorLineOpacity, '
      'lineWidth: $lineWidth, '
      'majorLineEvery: $majorLineEvery, '
      'minScreenSpacing: $minScreenSpacing, '
      'minRenderSpacing: $minRenderSpacing'
      ')';
}
