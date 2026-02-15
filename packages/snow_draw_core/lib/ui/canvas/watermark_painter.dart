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
/// is wasteful — the visual difference is imperceptible. Snapping to
/// a 64-pixel grid absorbs small fluctuations and keeps the cached
/// picture valid across many consecutive frames.
const double _sizeBucket = 64;

double _snap(double value) =>
    (value / _sizeBucket).ceilToDouble() * _sizeBucket;

/// Caches the tiled watermark as a [ui.Picture] so repeated frames
/// skip text layout and the O(n) tiling loop.
///
/// The cache is invalidated when either the [WatermarkConfig] or the
/// viewport size bucket changes. During interactive editing the
/// dynamic painter repaints on every pointer-move, but the watermark
/// itself is static — replaying a cached picture is orders of
/// magnitude cheaper than re-laying-out a [TextPainter] and painting
/// thousands of tiles each frame.
class WatermarkPainterCache {
  WatermarkConfig? _config;
  Size? _viewportSize;
  ui.Picture? _picture;

  /// Paints the watermark onto [canvas], reusing a cached picture
  /// when the config and viewport size bucket have not changed.
  void paint({
    required Canvas canvas,
    required Size viewportSize,
    required WatermarkConfig config,
    double scaleFactor = 1,
    Offset cameraPosition = Offset.zero,
  }) {
    // The caller (resolveWatermarkLayer) already filters disabled
    // configs, but guard against direct calls with no-op configs to
    // avoid unnecessary canvas state changes.
    if (config.text.isEmpty || config.opacity <= 0) {
      return;
    }

    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;

    // The caller's canvas is in world space (translated + scaled).
    // Undo that so the watermark renders in screen pixels.
    canvas
      ..save()
      ..scale(1 / scale, 1 / scale)
      ..translate(-cameraPosition.dx, -cameraPosition.dy);

    final picture = _resolve(viewportSize: viewportSize, config: config);

    // Clip to the viewport so rotated tiles don't bleed outside.
    // No saveLayer needed — the text color already has its alpha
    // baked in and there is no compositing blend mode to apply.
    canvas
      ..clipRect(Offset.zero & viewportSize)
      ..drawPicture(picture)
      ..restore();
  }

  /// Discards the cached picture so the next [paint] call rebuilds
  /// it from scratch.
  void invalidate() {
    _picture?.dispose();
    _picture = null;
    _config = null;
    _viewportSize = null;
  }

  ui.Picture _resolve({
    required Size viewportSize,
    required WatermarkConfig config,
  }) {
    // Snap the viewport to a coarse grid so small resize deltas
    // (e.g. during a window drag) reuse the existing picture.
    final snapped = Size(
      _snap(viewportSize.width),
      _snap(viewportSize.height),
    );

    if (_picture != null &&
        _config == config &&
        _viewportSize == snapped) {
      return _picture!;
    }

    _picture?.dispose();
    _picture = _record(viewportSize: snapped, config: config);
    _config = config;
    _viewportSize = snapped;
    return _picture!;
  }

  /// Computes the axis-aligned bounding box of the viewport rectangle
  /// after rotating it by [angleRad] around its [center].
  ///
  /// Instead of using the circumscribed circle (which over-estimates
  /// by ~57 %), this computes the tight AABB of the rotated corners.
  /// The tiling loop then iterates only over tiles that can actually
  /// intersect the visible area.
  static Rect _rotatedViewportAabb(
    Size size,
    Offset center,
    double angleRad,
  ) {
    final cosA = math.cos(angleRad).abs();
    final sinA = math.sin(angleRad).abs();
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final aabbHalfW = halfW * cosA + halfH * sinA;
    final aabbHalfH = halfW * sinA + halfH * cosA;
    return Rect.fromCenter(
      center: center,
      width: aabbHalfW * 2,
      height: aabbHalfH * 2,
    );
  }

  static ui.Picture _record({
    required Size viewportSize,
    required WatermarkConfig config,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & viewportSize);

    final effectiveAlpha =
        (config.color.a * config.opacity).clamp(0.0, 1.0);

    // At 8-bit precision an alpha below 1/255 ≈ 0.004 maps to zero.
    if (effectiveAlpha < 0.004) {
      return recorder.endRecording();
    }

    final trimmedText = config.text.trim();
    if (trimmedText.isEmpty) {
      return recorder.endRecording();
    }

    final fontFamily = config.fontFamily.trim();

    final textPainter = TextPainter(
      text: TextSpan(
        text: trimmedText,
        style: TextStyle(
          color: config.color.withValues(alpha: effectiveAlpha),
          fontSize: config.fontSize,
          fontFamily: fontFamily.isEmpty ? null : fontFamily,
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

    final normalizedGap = config.gap.isFinite
        ? config.gap.clamp(
            ConfigDefaults.minWatermarkGap,
            ConfigDefaults.maxWatermarkGap,
          )
        : ConfigDefaults.defaultWatermarkGap;
    final stepX = math.max(1, tileWidth + normalizedGap);
    final stepY = math.max(1, tileHeight + normalizedGap);
    final angleRad = config.angle * math.pi / 180;
    final layerRect = Offset.zero & viewportSize;
    final center = layerRect.center;

    canvas
      ..translate(center.dx, center.dy)
      ..rotate(angleRad)
      ..translate(-center.dx, -center.dy);

    final aabb = _rotatedViewportAabb(viewportSize, center, -angleRad);

    final startX = aabb.left - stepX;
    final endX = aabb.right + stepX;
    final startY = aabb.top - stepY;
    final endY = aabb.bottom + stepY;
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

/// Global watermark picture cache shared by both canvas painters.
///
/// Both the static and dynamic painters render the same watermark
/// content — only the layer they paint on differs. Sharing a single
/// cache avoids recording the picture twice when the watermark moves
/// between layers (e.g. when dynamic content appears or disappears).
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
