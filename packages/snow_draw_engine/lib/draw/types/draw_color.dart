import 'package:meta/meta.dart';

/// Backend-agnostic color value stored as packed ARGB32 (`0xAARRGGBB`).
@immutable
final class DrawColor {
  /// Creates a color from packed ARGB32 (`0xAARRGGBB`).
  const DrawColor(int argb32) : argb32 = argb32 & 0xFFFFFFFF;

  /// Packed ARGB32 value (`0xAARRGGBB`).
  final int argb32;

  /// Alpha channel in `[0, 255]`.
  int get alpha => (argb32 >>> 24) & 0xFF;

  /// Red channel in `[0, 255]`.
  int get red => (argb32 >>> 16) & 0xFF;

  /// Green channel in `[0, 255]`.
  int get green => (argb32 >>> 8) & 0xFF;

  /// Blue channel in `[0, 255]`.
  int get blue => argb32 & 0xFF;

  /// Normalized alpha in `[0, 1]`.
  double get a => alpha / 255;

  /// Normalized red in `[0, 1]`.
  double get r => red / 255;

  /// Normalized green in `[0, 1]`.
  double get g => green / 255;

  /// Normalized blue in `[0, 1]`.
  double get b => blue / 255;

  /// Returns this color as packed ARGB32 (`0xAARRGGBB`).
  int toARGB32() => argb32;

  /// Returns a copy with [alpha] (0-255).
  DrawColor withAlpha(int alpha) {
    final normalizedAlpha = alpha.clamp(0, 255);
    return DrawColor((normalizedAlpha << 24) | (argb32 & 0x00FFFFFF));
  }

  /// Returns a copy with optional normalized channels in `[0, 1]`.
  ///
  /// This mirrors Flutter's `Color.withValues` API for alpha-driven updates
  /// used in reducers/encoders during migration.
  DrawColor withValues({
    double? alpha,
    double? red,
    double? green,
    double? blue,
  }) {
    int resolve(double? value, int fallback) {
      if (value == null) {
        return fallback;
      }
      final normalized = value.clamp(0.0, 1.0);
      return (normalized * 255).round().clamp(0, 255);
    }

    final nextAlpha = resolve(alpha, this.alpha);
    final nextRed = resolve(red, this.red);
    final nextGreen = resolve(green, this.green);
    final nextBlue = resolve(blue, this.blue);
    return DrawColor(
      (nextAlpha << 24) | (nextRed << 16) | (nextGreen << 8) | nextBlue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DrawColor && other.argb32 == argb32;

  @override
  int get hashCode => argb32.hashCode;

  @override
  String toString() =>
      'DrawColor(0x${argb32.toRadixString(16).padLeft(8, '0')})';
}
