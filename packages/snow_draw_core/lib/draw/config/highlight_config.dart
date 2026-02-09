part of 'draw_config.dart';

/// Global highlight mask configuration.
@immutable
class HighlightMaskConfig {
  const HighlightMaskConfig({
    this.maskColor = ConfigDefaults.defaultMaskColor,
    this.maskOpacity = 0,
  }) : assert(
         maskOpacity >= 0 && maskOpacity <= 1,
         'maskOpacity must be in [0, 1]',
       );

  /// Mask color applied to the canvas.
  final Color maskColor;

  /// Mask opacity multiplier applied to [maskColor].
  final double maskOpacity;

  HighlightMaskConfig copyWith({Color? maskColor, double? maskOpacity}) =>
      HighlightMaskConfig(
        maskColor: maskColor ?? this.maskColor,
        maskOpacity: maskOpacity ?? this.maskOpacity,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlightMaskConfig &&
          other.maskColor == maskColor &&
          other.maskOpacity == maskOpacity;

  @override
  int get hashCode => Object.hash(maskColor, maskOpacity);

  @override
  String toString() =>
      'HighlightMaskConfig(maskColor: $maskColor, maskOpacity: $maskOpacity)';
}
