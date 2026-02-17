import 'dart:math' as math;
import 'dart:typed_data';
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
    if (_canUseTwoPointStrokeFastPath(
      data: data,
      strokeOpacity: strokeOpacity,
      fillOpacity: fillOpacity,
    )) {
      if (_renderTwoPointStrokeFastPath(
        canvas: canvas,
        element: element,
        data: data,
        strokeOpacity: strokeOpacity,
      )) {
        return;
      }
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

  bool _canUseTwoPointStrokeFastPath({
    required LineData data,
    required double strokeOpacity,
    required double fillOpacity,
  }) =>
      fillOpacity <= 0 &&
      strokeOpacity > 0 &&
      data.strokeWidth > 0 &&
      data.points.length == 2 &&
      !_isClosed(data);

  bool _renderTwoPointStrokeFastPath({
    required Canvas canvas,
    required ElementState element,
    required LineData data,
    required double strokeOpacity,
  }) {
    final rect = element.rect;
    if (!rect.width.isFinite ||
        !rect.height.isFinite ||
        rect.width < 0 ||
        rect.height < 0) {
      return false;
    }

    final startPoint = data.points.first;
    final endPoint = data.points.last;
    final start = Offset(startPoint.x * rect.width, startPoint.y * rect.height);
    final end = Offset(endPoint.x * rect.width, endPoint.y * rect.height);
    if (!_isFiniteOffset(start) || !_isFiniteOffset(end)) {
      return false;
    }

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    final strokeColor = data.color.withValues(alpha: strokeOpacity);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor
      ..isAntiAlias = true;

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawLine(start, end, strokePaint);
      case StrokeStyle.dashed:
        final dashLength = data.strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        _drawDashedSegment(
          canvas: canvas,
          start: start,
          end: end,
          paint: strokePaint,
          dashLength: dashLength,
          gapLength: gapLength,
        );
      case StrokeStyle.dotted:
        final dotPositions = _buildDottedSegmentPositions(
          start: start,
          end: end,
          spacing: data.strokeWidth * 2.0,
        );
        if (dotPositions.isNotEmpty) {
          final dotPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = data.strokeWidth
            ..strokeCap = StrokeCap.round
            ..color = strokeColor
            ..isAntiAlias = true;
          canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
        }
    }

    canvas.restore();
    return true;
  }

  void _drawDashedSegment({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
    required double dashLength,
    required double gapLength,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0 || !length.isFinite) {
      canvas.drawLine(start, end, paint);
      return;
    }

    final unitX = dx / length;
    final unitY = dy / length;
    var distance = 0.0;
    while (distance < length) {
      final dashEnd = math.min(distance + dashLength, length);
      final dashStartOffset = Offset(
        start.dx + unitX * distance,
        start.dy + unitY * distance,
      );
      final dashEndOffset = Offset(
        start.dx + unitX * dashEnd,
        start.dy + unitY * dashEnd,
      );
      canvas.drawLine(dashStartOffset, dashEndOffset, paint);
      distance = dashEnd + gapLength;
    }
  }

  Float32List _buildDottedSegmentPositions({
    required Offset start,
    required Offset end,
    required double spacing,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0 || !length.isFinite) {
      return Float32List.fromList([start.dx, start.dy]);
    }

    final safeSpacing = spacing <= 0 ? 1.0 : spacing;
    final dotCount = (length / safeSpacing).floor() + 1;
    final positions = Float32List(dotCount * 2);
    final unitX = dx / length;
    final unitY = dy / length;

    var index = 0;
    var distance = 0.0;
    while (distance < length && index < positions.length) {
      positions[index++] = start.dx + unitX * distance;
      positions[index++] = start.dy + unitY * distance;
      distance += safeSpacing;
    }

    if (index < positions.length) {
      return Float32List.sublistView(positions, 0, index);
    }
    return positions;
  }

  bool _isFiniteOffset(Offset value) => value.dx.isFinite && value.dy.isFinite;
}
