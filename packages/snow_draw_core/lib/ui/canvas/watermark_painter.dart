import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';

const _maxWatermarkTiles = 6000;

/// Paints a tiled text watermark as a viewport overlay.
///
/// Rendering is done in screen coordinates so watermark spacing and typography
/// stay stable regardless of camera zoom.
void paintWatermark({
  required Canvas canvas,
  required Size viewportSize,
  required WatermarkConfig config,
  double scaleFactor = 1,
  Offset cameraPosition = Offset.zero,
}) {
  final text = config.text.trim();
  if (text.isEmpty || config.opacity <= 0 || config.color.a <= 0) {
    return;
  }

  final effectiveAlpha = (config.color.a * config.opacity).clamp(0.0, 1.0);
  if (effectiveAlpha <= 0) {
    return;
  }

  final scale = scaleFactor == 0 ? 1.0 : scaleFactor;

  // Painter canvas is in world space; transform back to screen space.
  canvas
    ..save()
    ..scale(1 / scale, 1 / scale)
    ..translate(-cameraPosition.dx, -cameraPosition.dy);

  final layerRect = Offset.zero & viewportSize;
  canvas
    ..saveLayer(layerRect, Paint())
    ..clipRect(layerRect);

  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: config.color.withValues(alpha: effectiveAlpha),
        fontSize: config.fontSize,
        fontFamily: _resolveFontFamily(config.fontFamily),
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  final tileWidth = textPainter.width;
  final tileHeight = textPainter.height;
  if (tileWidth <= 0 || tileHeight <= 0) {
    canvas
      ..restore()
      ..restore();
    return;
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
  final center = layerRect.center;
  final radius = math.sqrt(
    layerRect.width * layerRect.width + layerRect.height * layerRect.height,
  );

  canvas
    ..translate(center.dx, center.dy)
    ..rotate(angleRad)
    ..translate(-center.dx, -center.dy);

  final startX = center.dx - radius - stepX;
  final endX = center.dx + radius + stepX;
  final startY = center.dy - radius - stepY;
  final endY = center.dy + radius + stepY;
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

  canvas
    ..restore()
    ..restore();
}

String? _resolveFontFamily(String fontFamily) {
  final trimmed = fontFamily.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
