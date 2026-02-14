part of 'draw_config.dart';

/// Object snapping configuration.
@immutable
class SnapConfig {
  const SnapConfig({
    this.enabled = ConfigDefaults.objectSnapEnabled,
    this.distance = ConfigDefaults.objectSnapDistance,
    this.enablePointSnaps = ConfigDefaults.objectSnapPointEnabled,
    this.enableGapSnaps = ConfigDefaults.objectSnapGapEnabled,
    this.enableArrowBinding = ConfigDefaults.arrowBindingEnabled,
    this.arrowBindingDistance = ConfigDefaults.arrowBindingDistance,
    this.showGuides = ConfigDefaults.objectSnapShowGuides,
    this.showGapSize = ConfigDefaults.objectSnapShowGapSize,
    this.lineColor = ConfigDefaults.objectSnapLineColor,
    this.lineWidth = ConfigDefaults.objectSnapLineWidth,
    this.markerSize = ConfigDefaults.objectSnapMarkerSize,
    this.gapDashLength = ConfigDefaults.objectSnapGapDashLength,
    this.gapDashGap = ConfigDefaults.objectSnapGapDashGap,
  }) : assert(distance >= 0, 'distance must be non-negative'),
       assert(
         arrowBindingDistance >= 0,
         'arrowBindingDistance must be non-negative',
       ),
       assert(lineWidth > 0, 'lineWidth must be positive'),
       assert(markerSize >= 0, 'markerSize must be non-negative'),
       assert(gapDashLength >= 0, 'gapDashLength must be non-negative'),
       assert(gapDashGap >= 0, 'gapDashGap must be non-negative');

  /// Whether object snapping is enabled.
  final bool enabled;

  /// Base snap distance in screen pixels.
  final double distance;

  /// Enable point snapping (corners/centers/edges).
  final bool enablePointSnaps;

  /// Enable gap snapping (equal spacing).
  final bool enableGapSnaps;

  /// Enable arrow endpoint binding to elements.
  final bool enableArrowBinding;

  /// Snap distance for arrow binding in screen pixels.
  final double arrowBindingDistance;

  /// Whether to render snap guides.
  final bool showGuides;

  /// Whether to render gap size labels.
  final bool showGapSize;

  /// Color for snap guides.
  final Color lineColor;

  /// Stroke width for snap guides.
  final double lineWidth;

  /// Cross/tick marker size in screen pixels.
  final double markerSize;

  /// Dash length for gap guides.
  final double gapDashLength;

  /// Dash gap length for gap guides.
  final double gapDashGap;

  SnapConfig copyWith({
    bool? enabled,
    double? distance,
    bool? enablePointSnaps,
    bool? enableGapSnaps,
    bool? enableArrowBinding,
    double? arrowBindingDistance,
    bool? showGuides,
    bool? showGapSize,
    Color? lineColor,
    double? lineWidth,
    double? markerSize,
    double? gapDashLength,
    double? gapDashGap,
  }) {
    final nextEnabled = enabled ?? this.enabled;
    final nextDistance = distance ?? this.distance;
    final nextEnablePointSnaps = enablePointSnaps ?? this.enablePointSnaps;
    final nextEnableGapSnaps = enableGapSnaps ?? this.enableGapSnaps;
    final nextEnableArrowBinding =
        enableArrowBinding ?? this.enableArrowBinding;
    final nextArrowBindingDistance =
        arrowBindingDistance ?? this.arrowBindingDistance;
    final nextShowGuides = showGuides ?? this.showGuides;
    final nextShowGapSize = showGapSize ?? this.showGapSize;
    final nextLineColor = lineColor ?? this.lineColor;
    final nextLineWidth = lineWidth ?? this.lineWidth;
    final nextMarkerSize = markerSize ?? this.markerSize;
    final nextGapDashLength = gapDashLength ?? this.gapDashLength;
    final nextGapDashGap = gapDashGap ?? this.gapDashGap;
    if (nextEnabled == this.enabled &&
        nextDistance == this.distance &&
        nextEnablePointSnaps == this.enablePointSnaps &&
        nextEnableGapSnaps == this.enableGapSnaps &&
        nextEnableArrowBinding == this.enableArrowBinding &&
        nextArrowBindingDistance == this.arrowBindingDistance &&
        nextShowGuides == this.showGuides &&
        nextShowGapSize == this.showGapSize &&
        nextLineColor == this.lineColor &&
        nextLineWidth == this.lineWidth &&
        nextMarkerSize == this.markerSize &&
        nextGapDashLength == this.gapDashLength &&
        nextGapDashGap == this.gapDashGap) {
      return this;
    }
    return SnapConfig(
      enabled: nextEnabled,
      distance: nextDistance,
      enablePointSnaps: nextEnablePointSnaps,
      enableGapSnaps: nextEnableGapSnaps,
      enableArrowBinding: nextEnableArrowBinding,
      arrowBindingDistance: nextArrowBindingDistance,
      showGuides: nextShowGuides,
      showGapSize: nextShowGapSize,
      lineColor: nextLineColor,
      lineWidth: nextLineWidth,
      markerSize: nextMarkerSize,
      gapDashLength: nextGapDashLength,
      gapDashGap: nextGapDashGap,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapConfig &&
          other.enabled == enabled &&
          other.distance == distance &&
          other.enablePointSnaps == enablePointSnaps &&
          other.enableGapSnaps == enableGapSnaps &&
          other.enableArrowBinding == enableArrowBinding &&
          other.arrowBindingDistance == arrowBindingDistance &&
          other.showGuides == showGuides &&
          other.showGapSize == showGapSize &&
          other.lineColor == lineColor &&
          other.lineWidth == lineWidth &&
          other.markerSize == markerSize &&
          other.gapDashLength == gapDashLength &&
          other.gapDashGap == gapDashGap;

  @override
  int get hashCode => Object.hash(
    enabled,
    distance,
    enablePointSnaps,
    enableGapSnaps,
    enableArrowBinding,
    arrowBindingDistance,
    showGuides,
    showGapSize,
    lineColor,
    lineWidth,
    markerSize,
    gapDashLength,
    gapDashGap,
  );

  @override
  String toString() =>
      'SnapConfig('
      'enabled: $enabled, '
      'distance: $distance, '
      'enablePointSnaps: $enablePointSnaps, '
      'enableGapSnaps: $enableGapSnaps, '
      'enableArrowBinding: $enableArrowBinding, '
      'arrowBindingDistance: $arrowBindingDistance, '
      'showGuides: $showGuides, '
      'showGapSize: $showGapSize, '
      'lineColor: $lineColor, '
      'lineWidth: $lineWidth, '
      'markerSize: $markerSize, '
      'gapDashLength: $gapDashLength, '
      'gapDashGap: $gapDashGap'
      ')';
}
