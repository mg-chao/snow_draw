import 'dart:math' as math;
import 'dart:ui';

import '../arrow/arrow_visual_cache.dart';
import '../stroke/two_point_stroke_utils.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'element_type_renderer.dart';
import 'stroke_pattern_utils.dart';

class LineRenderer extends ElementTypeRenderer {
  const LineRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! LineData) {
      throw StateError(
        'LineRenderer can only render LineData (got ${data.runtimeType})',
      );
    }
    final _ = scaleFactor;

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
          rect: element.rect,
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

    final cached = arrowVisualCache.resolve(element: element, data: data);
    final shouldFill = fillOpacity > 0 && _isClosed(data);
    final shouldStroke = strokeOpacity > 0 && data.strokeWidth > 0;
    if (!shouldFill && !shouldStroke) {
      return;
    }

    final rect = element.rect;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

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

    if (shouldStroke) {
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

      if (data.strokeStyle == StrokeStyle.dotted) {
        final dotPositions = cached.dotPositions!;
        if (dotPositions.isNotEmpty) {
          final dotPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cached.dotRadius * 2
            ..strokeCap = StrokeCap.round
            ..color = strokeColor
            ..isAntiAlias = true;
          canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
        }
      } else {
        canvas.drawPath(cached.combinedStrokePath!, strokePaint);
      }
    }

    canvas.restore();
  }

  bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;
}
