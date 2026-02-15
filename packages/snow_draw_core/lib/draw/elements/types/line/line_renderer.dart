import 'dart:math' as math;
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/stroke_pattern_utils.dart';
import '../../core/element_renderer.dart';
import '../arrow/arrow_visual_cache.dart';
import 'line_data.dart';

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

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 && fillOpacity <= 0) {
      return;
    }

    final cached = arrowVisualCache.resolve(element: element, data: data);
    if (cached.geometry.localPoints.length < 2) {
      return;
    }

    final shouldFill =
        fillOpacity > 0 &&
        _isClosed(data) &&
        cached.geometry.localPoints.length > 2;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    if (shouldFill) {
      final fillPath = Path()
        ..addPath(cached.shaftPath, Offset.zero)
        ..close();
      if (data.fillStyle == FillStyle.solid) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = data.fillColor.withValues(alpha: fillOpacity)
          ..isAntiAlias = true;
        canvas.drawPath(fillPath, paint);
      } else {
        final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 4.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        final fillColor = data.fillColor.withValues(alpha: fillOpacity);
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

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = data.color.withValues(alpha: strokeOpacity)
        ..isAntiAlias = true;

      if (data.strokeStyle == StrokeStyle.dotted) {
        final dotPositions = cached.dotPositions;
        if (dotPositions != null && dotPositions.isNotEmpty) {
          final dotPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cached.dotRadius * 2
            ..strokeCap = StrokeCap.round
            ..color = data.color.withValues(alpha: strokeOpacity)
            ..isAntiAlias = true;
          canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
        }
      } else {
        final combinedPath = cached.combinedStrokePath;
        if (combinedPath != null) {
          canvas.drawPath(combinedPath, strokePaint);
        }
      }
    }

    canvas.restore();
  }

  bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;
}
