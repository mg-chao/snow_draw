import 'dart:ui';

import 'package:flutter/material.dart';

import '../../draw/models/camera_state.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';
import '../../draw/utils/stroke_pattern_utils.dart';
import 'free_draw_creation_preview_cache.dart';

/// Render key for the dedicated free-draw creation preview layer.
///
/// Keeps high-frequency free-draw preview invalidation isolated from the
/// general dynamic scene key so long strokes do not force unrelated repaint
/// work.
@immutable
class FreeDrawPreviewRenderKey {
  const FreeDrawPreviewRenderKey({
    required this.camera,
    required this.scaleFactor,
    this.preview,
  });

  final CameraState camera;
  final double scaleFactor;
  final FreeDrawPreviewSnapshot? preview;

  bool get hasPreview => preview != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeDrawPreviewRenderKey &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor &&
          other.preview == preview;

  @override
  int get hashCode => Object.hash(camera, scaleFactor, preview);
}

/// Snapshot of an in-progress free-draw stroke used by the preview painter.
///
/// The mutable point/path references are compared by identity while [revision]
/// drives visual invalidation.
@immutable
class FreeDrawPreviewSnapshot {
  const FreeDrawPreviewSnapshot({
    required this.elementId,
    required this.points,
    required this.previewPath,
    required this.strokeColor,
    required this.strokeWidth,
    required this.strokeStyle,
    required this.opacity,
    required this.isLineActive,
    required this.lineAnchor,
    required this.lineCurrent,
    required this.revision,
  });

  final String elementId;
  final List<DrawPoint> points;
  final Path? previewPath;
  final Color strokeColor;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final double opacity;
  final bool isLineActive;
  final DrawPoint? lineAnchor;
  final DrawPoint? lineCurrent;
  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeDrawPreviewSnapshot &&
          other.elementId == elementId &&
          identical(other.points, points) &&
          identical(other.previewPath, previewPath) &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle &&
          other.opacity == opacity &&
          other.isLineActive == isLineActive &&
          other.lineAnchor == lineAnchor &&
          other.lineCurrent == lineCurrent &&
          other.revision == revision;

  @override
  int get hashCode => Object.hash(
    elementId,
    identityHashCode(points),
    identityHashCode(previewPath),
    strokeColor,
    strokeWidth,
    strokeStyle,
    opacity,
    isLineActive,
    lineAnchor,
    lineCurrent,
    revision,
  );
}

/// Paints low-latency free-draw creation previews on a dedicated layer.
class FreeDrawPreviewPainter extends CustomPainter {
  const FreeDrawPreviewPainter({required this.renderKey});

  static final _previewCache = FreeDrawCreationPreviewCache();
  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static final _dotPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final _pointPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  final FreeDrawPreviewRenderKey renderKey;

  @override
  void paint(Canvas canvas, Size size) {
    final preview = renderKey.preview;
    if (preview == null) {
      _previewCache.clear();
      return;
    }

    final points = preview.points;
    if (points.isEmpty) {
      _previewCache.clear();
      return;
    }

    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;
    final camera = renderKey.camera;
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    final strokeOpacity = (preview.strokeColor.a * preview.opacity).clamp(
      0.0,
      1.0,
    );
    if (strokeOpacity <= 0 || preview.strokeWidth <= 0) {
      _previewCache.clear();
      return;
    }

    final strokeColor = preview.strokeColor.withValues(alpha: strokeOpacity);
    final strokePaint = _strokePaint
      ..strokeWidth = preview.strokeWidth
      ..color = strokeColor;

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);
    try {
      if (preview.strokeStyle == StrokeStyle.solid) {
        final cachedPointCount = _resolveSolidPreviewPointCount(preview);
        if (cachedPointCount > 1) {
          _previewCache
            ..sync(
              elementId: preview.elementId,
              points: points,
              visiblePointCount: cachedPointCount,
              signature: FreeDrawPreviewStrokeSignature(
                strokeStyle: preview.strokeStyle,
                strokeWidth: preview.strokeWidth,
                strokeColor: strokeColor,
              ),
              strokePaint: strokePaint,
            )
            ..paint(
              canvas: canvas,
              viewportRect: viewportRect,
              strokePaint: strokePaint,
            );
        } else {
          _previewCache.clear();
        }
      } else {
        _previewCache.clear();
        final previewPath = preview.previewPath;
        if (previewPath != null) {
          _drawFreeDrawStrokePath(
            canvas: canvas,
            path: previewPath,
            snapshot: preview,
            strokePaint: strokePaint,
            strokeColor: strokeColor,
          );
        }
      }

      if (preview.isLineActive &&
          preview.lineAnchor != null &&
          preview.lineCurrent != null) {
        final anchor = preview.lineAnchor!;
        final current = preview.lineCurrent!;
        if (preview.strokeStyle == StrokeStyle.solid) {
          canvas.drawLine(
            Offset(anchor.x, anchor.y),
            Offset(current.x, current.y),
            strokePaint,
          );
        } else {
          final activeLinePath = Path()
            ..moveTo(anchor.x, anchor.y)
            ..lineTo(current.x, current.y);
          _drawFreeDrawStrokePath(
            canvas: canvas,
            path: activeLinePath,
            snapshot: preview,
            strokePaint: strokePaint,
            strokeColor: strokeColor,
          );
        }
      }

      final isSinglePointStroke =
          points.length == 1 ||
          (points.length == 2 &&
              points.first.x == points.last.x &&
              points.first.y == points.last.y);
      if (isSinglePointStroke && !preview.isLineActive) {
        final point = points.first;
        final pointPaint = _pointPaint..color = strokeColor;
        canvas.drawCircle(
          Offset(point.x, point.y),
          preview.strokeWidth / 2,
          pointPaint,
        );
      }
    } finally {
      canvas.restore();
    }
  }

  int _resolveSolidPreviewPointCount(FreeDrawPreviewSnapshot preview) {
    final points = preview.points;
    if (points.isEmpty) {
      return 0;
    }
    if (!preview.isLineActive) {
      return points.length;
    }
    if (points.length <= 2) {
      return 0;
    }
    return points.length - 1;
  }

  void _drawFreeDrawStrokePath({
    required Canvas canvas,
    required Path path,
    required FreeDrawPreviewSnapshot snapshot,
    required Paint strokePaint,
    required Color strokeColor,
  }) {
    switch (snapshot.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawPath(path, strokePaint);
      case StrokeStyle.dashed:
        final dashLength = snapshot.strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        final dashedPath = buildDashedPath(path, dashLength, gapLength);
        canvas.drawPath(dashedPath, strokePaint);
      case StrokeStyle.dotted:
        final dotSpacing = snapshot.strokeWidth * 2.0;
        final dotRadius = snapshot.strokeWidth * 0.5;
        final dotPositions = buildDotPositions(path, dotSpacing);
        if (dotPositions.isEmpty) {
          return;
        }
        final dotPaint = _dotPaint
          ..strokeWidth = dotRadius * 2
          ..color = strokeColor;
        canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FreeDrawPreviewPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;
}
