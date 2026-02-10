import 'dart:math' as math;
import 'dart:ui';

import '../../draw/config/draw_config.dart';
import '../../draw/elements/types/highlight/highlight_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';

void paintHighlightMask({
  required Canvas canvas,
  required List<ElementState> highlights,
  required DrawRect viewportRect,
  required HighlightMaskConfig maskConfig,
}) {
  if (maskConfig.maskOpacity <= 0) {
    return;
  }

  if (highlights.isEmpty) {
    return;
  }

  final effectiveAlpha = (maskConfig.maskColor.a * maskConfig.maskOpacity)
      .clamp(0.0, 1.0);
  if (effectiveAlpha <= 0) {
    return;
  }

  final layerRect = Rect.fromLTWH(
    viewportRect.minX,
    viewportRect.minY,
    viewportRect.width,
    viewportRect.height,
  );

  canvas.saveLayer(layerRect, Paint());

  final maskPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = maskConfig.maskColor.withValues(alpha: effectiveAlpha);
  canvas.drawRect(layerRect, maskPaint);

  final clearPaint = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.clear
    ..isAntiAlias = true;

  for (final element in highlights) {
    final data = element.data as HighlightData;
    final inflate = data.strokeWidth / 2;
    final rect = element.rect;
    final cullRect = _buildCullRect(
      rect: rect,
      rotation: element.rotation,
      inflate: inflate,
    );
    final expanded = Rect.fromLTWH(
      rect.minX - inflate,
      rect.minY - inflate,
      rect.width + inflate * 2,
      rect.height + inflate * 2,
    );

    if (!_rectsIntersect(cullRect, viewportRect)) {
      continue;
    }

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    if (data.shape == HighlightShape.rectangle) {
      canvas.drawRect(expanded, clearPaint);
    } else {
      canvas.drawOval(expanded, clearPaint);
    }
    canvas.restore();
  }

  canvas.restore();
}

bool _rectsIntersect(DrawRect a, DrawRect b) =>
    a.minX <= b.maxX &&
    a.maxX >= b.minX &&
    a.minY <= b.maxY &&
    a.maxY >= b.minY;

DrawRect _buildCullRect({
  required DrawRect rect,
  required double rotation,
  required double inflate,
}) {
  if (rotation == 0) {
    return DrawRect(
      minX: rect.minX - inflate,
      minY: rect.minY - inflate,
      maxX: rect.maxX + inflate,
      maxY: rect.maxY + inflate,
    );
  }

  final cx = rect.centerX;
  final cy = rect.centerY;
  final cosTheta = math.cos(rotation).abs();
  final sinTheta = math.sin(rotation).abs();
  final halfWidth = rect.width / 2;
  final halfHeight = rect.height / 2;
  final rotatedHalfWidth = (halfWidth * cosTheta) + (halfHeight * sinTheta);
  final rotatedHalfHeight = (halfWidth * sinTheta) + (halfHeight * cosTheta);

  return DrawRect(
    minX: cx - rotatedHalfWidth - inflate,
    minY: cy - rotatedHalfHeight - inflate,
    maxX: cx + rotatedHalfWidth + inflate,
    maxY: cy + rotatedHalfHeight + inflate,
  );
}
