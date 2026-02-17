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
const _opaqueWhite = Color(0xFFFFFFFF);

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
class _WatermarkLayoutConfig {
  const _WatermarkLayoutConfig({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.gap,
  });

  factory _WatermarkLayoutConfig.fromConfig(WatermarkConfig config) {
    final normalizedGap = config.gap.isFinite
        ? config.gap.clamp(
            ConfigDefaults.minWatermarkGap,
            ConfigDefaults.maxWatermarkGap,
          )
        : ConfigDefaults.defaultWatermarkGap;

    return _WatermarkLayoutConfig(
      text: config.text.trim(),
      fontSize: config.fontSize,
      fontFamily: config.fontFamily.trim(),
      gap: normalizedGap,
    );
  }

  final String text;
  final double fontSize;
  final String fontFamily;
  final double gap;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _WatermarkLayoutConfig &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.gap == gap;

  @override
  int get hashCode => Object.hash(text, fontSize, fontFamily, gap);
}

@immutable
class _WatermarkRenderConfig {
  const _WatermarkRenderConfig({
    required this.layout,
    required this.color,
    required this.effectiveAlpha,
  });

  factory _WatermarkRenderConfig.fromConfig(WatermarkConfig config) {
    final effectiveAlpha = (config.color.a * config.opacity).clamp(0.0, 1.0);
    return _WatermarkRenderConfig(
      layout: _WatermarkLayoutConfig.fromConfig(config),
      color: config.color.withValues(alpha: effectiveAlpha),
      effectiveAlpha: effectiveAlpha,
    );
  }

  final _WatermarkLayoutConfig layout;
  final Color color;
  final double effectiveAlpha;

  bool get isVisible => layout.text.isNotEmpty && effectiveAlpha >= 0.004;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _WatermarkRenderConfig &&
          other.layout == layout &&
          other.color == color &&
          other.effectiveAlpha == effectiveAlpha;

  @override
  int get hashCode => Object.hash(layout, color, effectiveAlpha);
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
/// The tile cache key excludes rotation angle and tint because the cache is
/// recorded in unrotated screen space and uses a white-alpha shader tile.
/// Angle and color/opacity are applied at paint time, which keeps drag and
/// opacity interactions at full speed.
class WatermarkPainterCache {
  _WatermarkLayoutConfig? _tileConfig;
  ui.Image? _tileImage;
  ui.Shader? _tileShader;
  Color? _tileTintColor;
  Paint? _tileTintPaint;

  _WatermarkRenderConfig? _fallbackConfig;
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
    final renderConfig = _WatermarkRenderConfig.fromConfig(config);
    if (!renderConfig.isVisible) {
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

    final tilePaint = _resolveTilePaint(renderConfig);
    if (tilePaint != null) {
      _clearFallbackPictureCache();
      canvas.drawRect(cullRect, tilePaint);
    } else {
      final picture = _resolveFallbackPicture(
        viewportSize: viewportSize,
        renderConfig: renderConfig,
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

  Paint? _resolveTilePaint(_WatermarkRenderConfig renderConfig) {
    final layoutConfig = renderConfig.layout;
    if (_tileConfig != layoutConfig) {
      _rebuildTileCache(layoutConfig);
    }

    final shader = _tileShader;
    if (shader == null) {
      return null;
    }

    final tintColor = renderConfig.color;
    if (_tileTintPaint != null && _tileTintColor == tintColor) {
      return _tileTintPaint;
    }

    final paint = Paint()
      ..shader = shader
      ..colorFilter = ColorFilter.mode(tintColor, BlendMode.srcIn);
    _tileTintColor = tintColor;
    _tileTintPaint = paint;
    return paint;
  }

  void _rebuildTileCache(_WatermarkLayoutConfig layoutConfig) {
    _clearTileCache();
    _tileConfig = layoutConfig;

    final snapshot = _buildTileSnapshot(layoutConfig);
    if (snapshot == null) {
      // Remember failed snapshots for this config so fallback mode does not
      // retry expensive tile creation every frame.
      return;
    }

    _tileImage = snapshot.image;
    _tileShader = ui.ImageShader(
      snapshot.image,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      _identityMatrix4,
    );
  }

  void _clearTileCache() {
    _tileImage?.dispose();
    _tileImage = null;
    _tileShader = null;
    _tileTintColor = null;
    _tileTintPaint = null;
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
    required _WatermarkRenderConfig renderConfig,
  }) {
    // Snap the viewport to a coarse grid so small resize deltas
    // (for example during window drag) reuse the existing picture.
    final snapped = Size(_snap(viewportSize.width), _snap(viewportSize.height));

    if (_picture != null &&
        _fallbackConfig == renderConfig &&
        _fallbackViewportSize == snapped) {
      return _picture!;
    }

    _picture?.dispose();
    _picture = _recordFallbackPicture(
      viewportSize: snapped,
      renderConfig: renderConfig,
    );
    _fallbackConfig = renderConfig;
    _fallbackViewportSize = snapped;
    return _picture!;
  }

  static _WatermarkTileSnapshot? _buildTileSnapshot(
    _WatermarkLayoutConfig layoutConfig,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: layoutConfig.text,
        style: TextStyle(
          color: _opaqueWhite,
          fontSize: layoutConfig.fontSize,
          fontFamily: layoutConfig.fontFamily.isEmpty
              ? null
              : layoutConfig.fontFamily,
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

    final stepX = math.max(1, textWidth + layoutConfig.gap).toDouble();
    final stepY = math.max(1, textHeight + layoutConfig.gap).toDouble();
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
    required _WatermarkRenderConfig renderConfig,
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
        text: renderConfig.layout.text,
        style: TextStyle(
          color: renderConfig.color,
          fontSize: renderConfig.layout.fontSize,
          fontFamily: renderConfig.layout.fontFamily.isEmpty
              ? null
              : renderConfig.layout.fontFamily,
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

    final stepX = math.max(1, tileWidth + renderConfig.layout.gap).toDouble();
    final stepY = math.max(1, tileHeight + renderConfig.layout.gap).toDouble();

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
