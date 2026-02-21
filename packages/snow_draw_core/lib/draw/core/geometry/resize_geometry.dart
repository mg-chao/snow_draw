import '../../types/draw_rect.dart';

/// Pure resize geometry helpers.
class ResizeGeometry {
  const ResizeGeometry._();

  static ({double scaleX, double scaleY}) calculateScale({
    required DrawRect original,
    required DrawRect scaled,
    bool flipX = false,
    bool flipY = false,
  }) => (
    scaleX: _resolveAxisScale(
      originalSize: original.width,
      scaledSize: scaled.width,
      flip: flipX,
    ),
    scaleY: _resolveAxisScale(
      originalSize: original.height,
      scaledSize: scaled.height,
      flip: flipY,
    ),
  );

  static double _resolveAxisScale({
    required double originalSize,
    required double scaledSize,
    required bool flip,
  }) {
    final scale = originalSize == 0 ? 1.0 : scaledSize / originalSize;
    return flip ? -scale : scale;
  }
}
