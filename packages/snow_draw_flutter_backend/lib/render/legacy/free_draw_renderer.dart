import 'dart:math' as math;
import 'dart:ui';

import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'element_type_renderer.dart';
import 'free_draw_visual_cache.dart';
import 'stroke_pattern_utils.dart';
import 'two_point_stroke_utils.dart';

class FreeDrawRenderer extends ElementTypeRenderer {
  const FreeDrawRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;

  /// Clears the static shader cache.
  ///
  /// Call when switching documents or under memory pressure.
  static void clearCaches() {
    clearStrokePatternCaches();
    FreeDrawVisualCache.instance.clear();
  }

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawRenderer can only render FreeDrawData '
        '(got ${data.runtimeType})',
      );
    }
    final _ = scaleFactor;

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 && fillOpacity <= 0) {
      return;
    }

    if (canUseTwoPointStrokeFastPath(
          pointCount: data.points.length,
          strokeOpacity: strokeOpacity,
          fillOpacity: fillOpacity,
          strokeWidth: data.strokeWidth,
        ) &&
        renderTwoPointNormalizedStroke(
          canvas: canvas,
          rect: rect,
          rotation: element.rotation,
          startPoint: data.points.first,
          endPoint: data.points.last,
          strokeWidth: data.strokeWidth,
          strokeStyle: data.strokeStyle,
          strokeColor: Color(
            data.color.withValues(alpha: strokeOpacity).toARGB32(),
          ),
        )) {
      return;
    }

    final cached = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );
    if (cached.pointCount < 2) {
      return;
    }

    var picture = cached.getCachedPicture(opacity);
    if (picture == null && cached.shouldRecordPicture(opacity)) {
      final recorder = PictureRecorder();
      final recordCanvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, rect.width, rect.height),
      );
      _renderToCanvas(
        canvas: recordCanvas,
        data: data,
        rect: rect,
        cached: cached,
        strokeOpacity: strokeOpacity,
        fillOpacity: fillOpacity,
      );
      picture = recorder.endRecording();
      cached.setCachedPicture(picture, opacity);
    }

    _paintInElementSpace(
      canvas: canvas,
      rect: rect,
      rotation: element.rotation,
      paint: (localCanvas) {
        if (picture != null) {
          localCanvas.drawPicture(picture);
          return;
        }
        _renderToCanvas(
          canvas: localCanvas,
          data: data,
          rect: rect,
          cached: cached,
          strokeOpacity: strokeOpacity,
          fillOpacity: fillOpacity,
        );
      },
    );
  }

  void _renderToCanvas({
    required Canvas canvas,
    required FreeDrawData data,
    required DrawRect rect,
    required FreeDrawVisualEntry cached,
    required double strokeOpacity,
    required double fillOpacity,
  }) {
    final shouldFill =
        fillOpacity > 0 && _isClosed(data, rect) && cached.pointCount > 2;

    if (shouldFill) {
      final fillPath = cached.getOrBuildClosedFillPath();
      final fillColor = Color(
        data.fillColor.withValues(alpha: fillOpacity).toARGB32(),
      );
      if (data.fillStyle == FillStyle.solid) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor
          ..isAntiAlias = true;
        canvas.drawPath(fillPath, paint);
      } else {
        final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 4.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        final fillPaint = buildLineFillPaint(
          spacing: spacing,
          lineWidth: fillLineWidth,
          angle: _lineFillAngle,
          color: fillColor,
        );
        canvas.drawPath(fillPath, fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          final crossPaint = buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: fillColor,
          );
          canvas.drawPath(fillPath, crossPaint);
        }
      }
    }

    if (strokeOpacity <= 0 || data.strokeWidth <= 0) {
      return;
    }

    final strokeColor = Color(
      data.color.withValues(alpha: strokeOpacity).toARGB32(),
    );
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor
      ..isAntiAlias = true;

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawPath(cached.path, strokePaint);
      case StrokeStyle.dashed:
        canvas.drawPath(cached.strokePath!, strokePaint);
      case StrokeStyle.dotted:
        final dotPositions = cached.dotPositions!;
        if (dotPositions.isEmpty) {
          return;
        }
        final dotPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cached.dotRadius * 2
          ..strokeCap = StrokeCap.round
          ..color = strokeColor
          ..isAntiAlias = true;
        canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
    }
  }

  bool _isClosed(FreeDrawData data, DrawRect rect) {
    if (data.points.length < 3) {
      return false;
    }
    final first = data.points.first;
    final last = data.points.last;
    if (first == last) {
      return true;
    }
    const tolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= tolerance * tolerance;
  }

  void _paintInElementSpace({
    required Canvas canvas,
    required DrawRect rect,
    required double rotation,
    required void Function(Canvas canvas) paint,
  }) {
    canvas.save();
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);
    paint(canvas);
    canvas.restore();
  }
}
