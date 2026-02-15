part of 'draw_config.dart';

/// Global watermark configuration.
@immutable
class WatermarkConfig {
  const WatermarkConfig({
    this.color = ConfigDefaults.defaultWatermarkColor,
    this.text = ConfigDefaults.defaultWatermarkText,
    this.fontSize = ConfigDefaults.defaultWatermarkFontSize,
    this.fontFamily = ConfigDefaults.defaultWatermarkFontFamily,
    this.angle = ConfigDefaults.defaultWatermarkAngle,
    this.gap = ConfigDefaults.defaultWatermarkGap,
    this.opacity = ConfigDefaults.defaultWatermarkOpacity,
  }) : assert(fontSize > 0, 'fontSize must be > 0'),
       assert(
         gap >= ConfigDefaults.minWatermarkGap &&
             gap <= ConfigDefaults.maxWatermarkGap,
         'gap must be in [${ConfigDefaults.minWatermarkGap}, '
         '${ConfigDefaults.maxWatermarkGap}]',
       ),
       assert(opacity >= 0 && opacity <= 1, 'opacity must be in [0, 1]');

  /// Base text color.
  final Color color;

  /// Watermark label. Empty text disables rendering.
  final String text;

  /// Font size in logical pixels.
  final double fontSize;

  /// Font family name. `''` uses system fallback fonts.
  final String fontFamily;

  /// Clockwise text rotation angle in degrees.
  final double angle;

  /// Gap between tiled watermark labels.
  final double gap;

  /// Opacity multiplier applied on top of [color] alpha.
  final double opacity;

  WatermarkConfig copyWith({
    Color? color,
    String? text,
    double? fontSize,
    String? fontFamily,
    double? angle,
    double? gap,
    double? opacity,
  }) {
    final nextColor = color ?? this.color;
    final nextText = text ?? this.text;
    final nextFontSize = fontSize ?? this.fontSize;
    final nextFontFamily = fontFamily ?? this.fontFamily;
    final nextAngle = angle ?? this.angle;
    final nextGap = gap ?? this.gap;
    final nextOpacity = opacity ?? this.opacity;
    if (nextColor == this.color &&
        nextText == this.text &&
        nextFontSize == this.fontSize &&
        nextFontFamily == this.fontFamily &&
        nextAngle == this.angle &&
        nextGap == this.gap &&
        nextOpacity == this.opacity) {
      return this;
    }
    return WatermarkConfig(
      color: nextColor,
      text: nextText,
      fontSize: nextFontSize,
      fontFamily: nextFontFamily,
      angle: nextAngle,
      gap: nextGap,
      opacity: nextOpacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkConfig &&
          other.color == color &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.angle == angle &&
          other.gap == gap &&
          other.opacity == opacity;

  @override
  int get hashCode =>
      Object.hash(color, text, fontSize, fontFamily, angle, gap, opacity);

  @override
  String toString() =>
      'WatermarkConfig('
      'color: $color, '
      'text: $text, '
      'fontSize: $fontSize, '
      'fontFamily: $fontFamily, '
      'angle: $angle, '
      'gap: $gap, '
      'opacity: $opacity'
      ')';
}
