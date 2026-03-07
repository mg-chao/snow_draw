import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:snow_draw_engine/snow_draw_engine.dart';
import '../../extensions/draw_color_extensions.dart';
import 'highlight_mask_shader_manager.dart';

/// Paints a dimming mask over the viewport with holes for highlights.
///
/// Tries the GPU-accelerated shader path first. Falls back to the
/// path-difference CPU compositor when the shader is not available or the
/// highlight count exceeds the shader limit.
void paintHighlightMask({
  required Canvas canvas,
  required List<ElementState> highlights,
  required DrawRect viewportRect,
  required HighlightMaskConfig maskConfig,
  double scaleFactor = 1,
  Offset cameraPosition = Offset.zero,
}) {
  if (highlights.isEmpty) {
    return;
  }

  final effectiveAlpha = (maskConfig.maskColor.a * maskConfig.maskOpacity)
      .clamp(0.0, 1.0);
  if (effectiveAlpha <= 0) {
    return;
  }

  // Attempt GPU-accelerated path.
  final shaderManager = HighlightMaskShaderManager.instance;
  if (shaderManager.isReady) {
    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;

    // The canvas is currently in world-coordinate space (translated +
    // scaled). Undo that transform so the shader can draw in screen
    // pixels, then restore afterwards.
    canvas.save();
    try {
      canvas
        ..scale(1 / scale, 1 / scale)
        ..translate(-cameraPosition.dx, -cameraPosition.dy);

      final used = shaderManager.paintMask(
        canvas: canvas,
        highlights: highlights,
        viewportRect: viewportRect,
        maskConfig: maskConfig,
        scaleFactor: scale,
        cameraPosition: cameraPosition,
      );
      if (used) {
        return;
      }
    } finally {
      canvas.restore();
    }
  }

  // CPU fallback.
  _paintHighlightMaskFallback(
    canvas: canvas,
    highlights: highlights,
    viewportRect: viewportRect,
    maskConfig: maskConfig,
    effectiveAlpha: effectiveAlpha,
  );
}

/// Cached paints for the CPU fallback path to avoid allocating new
/// native paint objects on every frame.
final _fallbackLayerPaint = Paint();
final _fallbackMaskPaint = Paint()..style = PaintingStyle.fill;
final _fallbackClearPaint = Paint()
  ..style = PaintingStyle.fill
  ..blendMode = BlendMode.clear
  ..isAntiAlias = true;

final class _VisibleHighlightHole {
  const _VisibleHighlightHole({
    required this.expandedRect,
    required this.shape,
    required this.rotation,
    required this.centerX,
    required this.centerY,
  });

  final Rect expandedRect;
  final HighlightShape shape;
  final double rotation;
  final double centerX;
  final double centerY;
}

/// CPU fallback that fills the viewport rect minus highlight-hole geometry.
void _paintHighlightMaskFallback({
  required Canvas canvas,
  required List<ElementState> highlights,
  required DrawRect viewportRect,
  required HighlightMaskConfig maskConfig,
  required double effectiveAlpha,
}) {
  final layerRect = Rect.fromLTWH(
    viewportRect.minX,
    viewportRect.minY,
    viewportRect.width,
    viewportRect.height,
  );

  _fallbackMaskPaint.color = maskConfig.maskColor
      .withValues(alpha: effectiveAlpha)
      .toFlutterColor();
  final visibleHoles = _collectVisibleHighlightHoles(
    highlights: highlights,
    viewportRect: viewportRect,
  );
  if (visibleHoles.isEmpty) {
    canvas.drawRect(layerRect, _fallbackMaskPaint);
    return;
  }

  final holesPath = Path();
  for (final hole in visibleHoles) {
    _appendHighlightHolePath(holesPath: holesPath, hole: hole);
  }

  try {
    final maskPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(layerRect),
      holesPath,
    );
    canvas.drawPath(maskPath, _fallbackMaskPaint);
  } on Object {
    _paintHighlightMaskFallbackWithSaveLayer(
      canvas: canvas,
      layerRect: layerRect,
      visibleHoles: visibleHoles,
    );
  }
}

List<_VisibleHighlightHole> _collectVisibleHighlightHoles({
  required List<ElementState> highlights,
  required DrawRect viewportRect,
}) {
  final visibleHoles = <_VisibleHighlightHole>[];
  for (final element in highlights) {
    final data = element.data as HighlightData;
    final inflate = data.strokeWidth / 2;
    final rect = element.rect;
    final cullRect = _buildCullRect(
      rect: rect,
      rotation: element.rotation,
      inflate: inflate,
    );
    if (!_rectsIntersect(cullRect, viewportRect)) {
      continue;
    }

    visibleHoles.add(
      _VisibleHighlightHole(
        expandedRect: Rect.fromLTWH(
          rect.minX - inflate,
          rect.minY - inflate,
          rect.width + inflate * 2,
          rect.height + inflate * 2,
        ),
        shape: data.shape,
        rotation: element.rotation,
        centerX: rect.centerX,
        centerY: rect.centerY,
      ),
    );
  }
  return visibleHoles;
}

void _paintHighlightMaskFallbackWithSaveLayer({
  required Canvas canvas,
  required Rect layerRect,
  required List<_VisibleHighlightHole> visibleHoles,
}) {
  canvas
    ..saveLayer(layerRect, _fallbackLayerPaint)
    ..drawRect(layerRect, _fallbackMaskPaint);

  for (final hole in visibleHoles) {
    _drawHighlightHole(canvas: canvas, hole: hole, paint: _fallbackClearPaint);
  }

  canvas.restore();
}

void _appendHighlightHolePath({
  required Path holesPath,
  required _VisibleHighlightHole hole,
}) {
  if (hole.rotation == 0) {
    _addShapeToPath(
      path: holesPath,
      shape: hole.shape,
      rect: hole.expandedRect,
    );
    return;
  }

  final shapePath = Path();
  _addShapeToPath(path: shapePath, shape: hole.shape, rect: hole.expandedRect);
  holesPath.addPath(
    shapePath,
    Offset.zero,
    matrix4: _rotationMatrix(
      rotation: hole.rotation,
      centerX: hole.centerX,
      centerY: hole.centerY,
    ),
  );
}

void _drawHighlightHole({
  required Canvas canvas,
  required _VisibleHighlightHole hole,
  required Paint paint,
}) {
  if (hole.rotation == 0) {
    _drawShape(
      canvas: canvas,
      shape: hole.shape,
      rect: hole.expandedRect,
      paint: paint,
    );
    return;
  }

  canvas
    ..save()
    ..translate(hole.centerX, hole.centerY)
    ..rotate(hole.rotation)
    ..translate(-hole.centerX, -hole.centerY);
  _drawShape(
    canvas: canvas,
    shape: hole.shape,
    rect: hole.expandedRect,
    paint: paint,
  );
  canvas.restore();
}

void _addShapeToPath({
  required Path path,
  required HighlightShape shape,
  required Rect rect,
}) {
  switch (shape) {
    case HighlightShape.rectangle:
      path.addRect(rect);
    case HighlightShape.ellipse:
      path.addOval(rect);
  }
}

void _drawShape({
  required Canvas canvas,
  required HighlightShape shape,
  required Rect rect,
  required Paint paint,
}) {
  switch (shape) {
    case HighlightShape.rectangle:
      canvas.drawRect(rect, paint);
    case HighlightShape.ellipse:
      canvas.drawOval(rect, paint);
  }
}

Float64List _rotationMatrix({
  required double rotation,
  required double centerX,
  required double centerY,
}) {
  final cosTheta = math.cos(rotation);
  final sinTheta = math.sin(rotation);
  final tx = centerX - (centerX * cosTheta) + (centerY * sinTheta);
  final ty = centerY - (centerX * sinTheta) - (centerY * cosTheta);
  return Float64List.fromList([
    cosTheta,
    sinTheta,
    0,
    0,
    -sinTheta,
    cosTheta,
    0,
    0,
    0,
    0,
    1,
    0,
    tx,
    ty,
    0,
    1,
  ]);
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
