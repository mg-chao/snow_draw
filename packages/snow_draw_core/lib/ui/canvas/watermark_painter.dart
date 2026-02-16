import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';

/// Hard cap on the number of tiles to prevent runaway loops on
/// extreme viewport/gap combinations.
const _maxWatermarkTiles = 6000;

/// Coarse grid size for viewport snapping.
///
/// During interactive window resizing the viewport changes by a few
/// pixels every frame. Recording a new picture for each unique size
/// is wasteful; the visual difference is imperceptible. Snapping to
/// a 64-pixel grid absorbs small fluctuations and keeps the cached
/// picture valid across many consecutive frames.
const double _sizeBucket = 64;

double _snap(double value) =>
    (value / _sizeBucket).ceilToDouble() * _sizeBucket;

@immutable
class _WatermarkPictureConfig {
  const _WatermarkPictureConfig({
    required this.color,
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.gap,
    required this.effectiveAlpha,
  });

  factory _WatermarkPictureConfig.fromConfig(WatermarkConfig config) {
    final effectiveAlpha = (config.color.a * config.opacity).clamp(0.0, 1.0);
    final normalizedGap = config.gap.isFinite
        ? config.gap.clamp(
            ConfigDefaults.minWatermarkGap,
            ConfigDefaults.maxWatermarkGap,
          )
        : ConfigDefaults.defaultWatermarkGap;

    return _WatermarkPictureConfig(
      color: config.color.withValues(alpha: effectiveAlpha),
      text: config.text.trim(),
      fontSize: config.fontSize,
      fontFamily: config.fontFamily.trim(),
      gap: normalizedGap,
      effectiveAlpha: effectiveAlpha,
    );
  }

  final Color color;
  final String text;
  final double fontSize;
  final String fontFamily;
  final double gap;
  final double effectiveAlpha;

  bool get isVisible => text.isNotEmpty && effectiveAlpha >= 0.004;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _WatermarkPictureConfig &&
          other.color == color &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.gap == gap &&
          other.effectiveAlpha == effectiveAlpha;

  @override
  int get hashCode =>
      Object.hash(color, text, fontSize, fontFamily, gap, effectiveAlpha);
}

/// Caches the tiled watermark as a [ui.Picture] so repeated frames
/// skip text layout and the O(n) tiling loop.
///
/// The cache key excludes rotation angle: the picture is recorded in
/// unrotated screen space and the angle transform is applied at paint
/// time. This keeps angle-drag interactions at full speed.
class WatermarkPainterCache {
  _WatermarkPictureConfig? _pictureConfig;
  Size? _viewportSize;
  ui.Picture? _picture;

  /// Paints the watermark onto [canvas], reusing a cached picture when
  /// the non-angular config and viewport size bucket have not changed.
  void paint({
    required Canvas canvas,
    required Size viewportSize,
    required WatermarkConfig config,
    double scaleFactor = 1,
    Offset cameraPosition = Offset.zero,
  }) {
    final pictureConfig = _WatermarkPictureConfig.fromConfig(config);
    if (!pictureConfig.isVisible) {
      return;
    }

    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;

    // The caller's canvas is in world space (translated + scaled).
    // Undo that so the watermark renders in screen pixels.
    canvas
      ..save()
      ..scale(1 / scale, 1 / scale)
      ..translate(-cameraPosition.dx, -cameraPosition.dy);

    final picture = _resolve(
      viewportSize: viewportSize,
      pictureConfig: pictureConfig,
    );

    final layerRect = Offset.zero & viewportSize;
    final center = layerRect.center;

    // Clip to the viewport so rotated tiles do not bleed outside.
    canvas
      ..clipRect(layerRect)
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(config.angle * math.pi / 180)
      ..translate(-center.dx, -center.dy)
      ..drawPicture(picture)
      ..restore()
      ..restore();
  }

  /// Discards the cached picture so the next [paint] call rebuilds it.
  void invalidate() {
    _picture?.dispose();
    _picture = null;
    _pictureConfig = null;
    _viewportSize = null;
  }

  ui.Picture _resolve({
    required Size viewportSize,
    required _WatermarkPictureConfig pictureConfig,
  }) {
    // Snap the viewport to a coarse grid so small resize deltas
    // (for example during window drag) reuse the existing picture.
    final snapped = Size(_snap(viewportSize.width), _snap(viewportSize.height));

    if (_picture != null &&
        _pictureConfig == pictureConfig &&
        _viewportSize == snapped) {
      return _picture!;
    }

    _picture?.dispose();
    _picture = _record(viewportSize: snapped, pictureConfig: pictureConfig);
    _pictureConfig = pictureConfig;
    _viewportSize = snapped;
    return _picture!;
  }

  static ui.Picture _record({
    required Size viewportSize,
    required _WatermarkPictureConfig pictureConfig,
  }) {
    final layerRect = Offset.zero & viewportSize;
    final center = layerRect.center;

    // Record enough content to cover every rotation angle.
    final diagonal = math.sqrt(
      viewportSize.width * viewportSize.width +
          viewportSize.height * viewportSize.height,
    );
    final cullRect = Rect.fromCenter(
      center: center,
      width: diagonal,
      height: diagonal,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, cullRect);

    final textPainter = TextPainter(
      text: TextSpan(
        text: pictureConfig.text,
        style: TextStyle(
          color: pictureConfig.color,
          fontSize: pictureConfig.fontSize,
          fontFamily: pictureConfig.fontFamily.isEmpty
              ? null
              : pictureConfig.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final tileWidth = textPainter.width;
    final tileHeight = textPainter.height;
    if (tileWidth <= 0 || tileHeight <= 0) {
      textPainter.dispose();
      return recorder.endRecording();
    }

    final stepX = math.max(1, tileWidth + pictureConfig.gap);
    final stepY = math.max(1, tileHeight + pictureConfig.gap);

    final startX = cullRect.left - stepX;
    final endX = cullRect.right + stepX;
    final startY = cullRect.top - stepY;
    final endY = cullRect.bottom + stepY;
    var drawCount = 0;
    var row = 0;

    for (var y = startY; y <= endY; y += stepY) {
      final rowOffset = row.isEven ? 0.0 : stepX * 0.5;
      for (var x = startX; x <= endX; x += stepX) {
        textPainter.paint(canvas, Offset(x + rowOffset, y));
        drawCount += 1;
        if (drawCount >= _maxWatermarkTiles) {
          break;
        }
      }
      if (drawCount >= _maxWatermarkTiles) {
        break;
      }
      row += 1;
    }

    textPainter.dispose();
    return recorder.endRecording();
  }
}

/// Global watermark picture cache shared by canvas painters.
final watermarkPainterCache = WatermarkPainterCache();

/// Paints a tiled text watermark as a viewport overlay.
///
/// Delegates to [watermarkPainterCache] so repeated frames skip text
/// layout and the expensive tiling loop.
void paintWatermark({
  required Canvas canvas,
  required Size viewportSize,
  required WatermarkConfig config,
  double scaleFactor = 1,
  Offset cameraPosition = Offset.zero,
}) {
  watermarkPainterCache.paint(
    canvas: canvas,
    viewportSize: viewportSize,
    config: config,
    scaleFactor: scaleFactor,
    cameraPosition: cameraPosition,
  );
}
