import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';

/// Hard cap on the number of tiles to prevent runaway loops on
/// extreme viewport/gap combinations.
const _maxWatermarkTiles = 6000;

/// Maximum tile edge used by the shader-backed cache.
///
/// Very long labels can produce huge tile textures when combined with large
/// gaps. Cap edge length and fall back to viewport picture tiling when the
/// generated tile would be too large.
const _maxWatermarkTileExtent = 4096;

/// Coarse grid size for viewport snapping in picture-fallback mode.
///
/// During interactive window resizing the viewport changes by a few pixels
/// every frame. Recording a new picture for each unique size is wasteful;
/// the visual difference is imperceptible. Snapping to a 64-pixel grid
/// absorbs small fluctuations and keeps the cached picture valid across many
/// consecutive frames.
const double _sizeBucket = 64;

final _identityMatrix4 = Float64List.fromList(<double>[
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
]);

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

@immutable
class _WatermarkTileSnapshot {
  const _WatermarkTileSnapshot({required this.image});

  final ui.Image image;
}

/// Caches watermark paint resources so repeated frames avoid text layout.
///
/// Fast path: build a tiny shader tile and fill a rotated rect in one draw.
/// Fallback: when a tile would be excessively large, use viewport picture
/// tiling with coarse viewport-size bucketing.
///
/// The cache key excludes rotation angle because the cache is recorded in
/// unrotated screen space and angle is applied at paint time. This keeps
/// angle-drag interactions at full speed.
class WatermarkPainterCache {
  _WatermarkPictureConfig? _tileConfig;
  ui.Image? _tileImage;
  Paint? _tilePaint;

  _WatermarkPictureConfig? _fallbackConfig;
  Size? _fallbackViewportSize;
  ui.Picture? _picture;

  /// Paints the watermark onto [canvas], reusing a cached picture when
  /// the non-angular config has not changed.
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
    if (viewportSize.isEmpty) {
      return;
    }

    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;

    // The caller's canvas is in world space (translated + scaled).
    // Undo that so the watermark renders in screen pixels.
    canvas
      ..save()
      ..scale(1 / scale, 1 / scale)
      ..translate(-cameraPosition.dx, -cameraPosition.dy);

    final layerRect = Offset.zero & viewportSize;
    final center = layerRect.center;
    final diagonal = math.sqrt(
      viewportSize.width * viewportSize.width +
          viewportSize.height * viewportSize.height,
    );
    final cullRect = Rect.fromCenter(
      center: center,
      width: diagonal,
      height: diagonal,
    );

    // Clip to the viewport so rotated tiles do not bleed outside.
    canvas
      ..clipRect(layerRect)
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(config.angle * math.pi / 180)
      ..translate(-center.dx, -center.dy);

    final tilePaint = _resolveTilePaint(pictureConfig);
    if (tilePaint != null) {
      _clearFallbackPictureCache();
      canvas.drawRect(cullRect, tilePaint);
    } else {
      final picture = _resolveFallbackPicture(
        viewportSize: viewportSize,
        pictureConfig: pictureConfig,
      );
      canvas.drawPicture(picture);
    }

    canvas
      ..restore()
      ..restore();
  }

  /// Discards the cached picture so the next [paint] call rebuilds it.
  void invalidate() {
    _clearTileCache();
    _clearFallbackPictureCache();
  }

  Paint? _resolveTilePaint(_WatermarkPictureConfig pictureConfig) {
    if (_tileConfig == pictureConfig) {
      return _tilePaint;
    }

    _clearTileCache();

    final snapshot = _buildTileSnapshot(pictureConfig);
    if (snapshot == null) {
      // Remember failed snapshots for this config so fallback mode does not
      // retry expensive tile creation every frame.
      _tileConfig = pictureConfig;
      return null;
    }

    final shader = ui.ImageShader(
      snapshot.image,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      _identityMatrix4,
    );
    final paint = Paint()..shader = shader;
    _tileImage = snapshot.image;
    _tilePaint = paint;
    _tileConfig = pictureConfig;
    return paint;
  }

  void _clearTileCache() {
    _tileImage?.dispose();
    _tileImage = null;
    _tilePaint = null;
    _tileConfig = null;
  }

  void _clearFallbackPictureCache() {
    _picture?.dispose();
    _picture = null;
    _fallbackConfig = null;
    _fallbackViewportSize = null;
  }

  ui.Picture _resolveFallbackPicture({
    required Size viewportSize,
    required _WatermarkPictureConfig pictureConfig,
  }) {
    // Snap the viewport to a coarse grid so small resize deltas
    // (for example during window drag) reuse the existing picture.
    final snapped = Size(_snap(viewportSize.width), _snap(viewportSize.height));

    if (_picture != null &&
        _fallbackConfig == pictureConfig &&
        _fallbackViewportSize == snapped) {
      return _picture!;
    }

    _picture?.dispose();
    _picture = _recordFallbackPicture(
      viewportSize: snapped,
      pictureConfig: pictureConfig,
    );
    _fallbackConfig = pictureConfig;
    _fallbackViewportSize = snapped;
    return _picture!;
  }

  static _WatermarkTileSnapshot? _buildTileSnapshot(
    _WatermarkPictureConfig pictureConfig,
  ) {
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

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    if (textWidth <= 0 || textHeight <= 0) {
      textPainter.dispose();
      return null;
    }

    final stepX = math.max(1, textWidth + pictureConfig.gap).toDouble();
    final stepY = math.max(1, textHeight + pictureConfig.gap).toDouble();
    final tileWidth = (stepX * 2).ceil();
    final tileHeight = (stepY * 2).ceil();

    if (tileWidth > _maxWatermarkTileExtent ||
        tileHeight > _maxWatermarkTileExtent) {
      textPainter.dispose();
      return null;
    }

    final tileRect = Rect.fromLTWH(
      0,
      0,
      tileWidth.toDouble(),
      tileHeight.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, tileRect);
    final secondRowOffset = stepX * 0.5;

    textPainter
      ..paint(canvas, Offset.zero)
      ..paint(canvas, Offset(stepX, 0))
      ..paint(canvas, Offset(secondRowOffset, stepY))
      ..paint(canvas, Offset(secondRowOffset + stepX, stepY))
      ..dispose();

    final picture = recorder.endRecording();
    try {
      final image = picture.toImageSync(tileWidth, tileHeight);
      return _WatermarkTileSnapshot(image: image);
    } on Object {
      return null;
    } finally {
      picture.dispose();
    }
  }

  static ui.Picture _recordFallbackPicture({
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

    final stepX = math.max(1, tileWidth + pictureConfig.gap).toDouble();
    final stepY = math.max(1, tileHeight + pictureConfig.gap).toDouble();

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
