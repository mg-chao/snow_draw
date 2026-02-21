import 'dart:ui';

import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_visual_cache.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'element_type_renderer.dart';

class ArrowRenderer extends ElementTypeRenderer {
  const ArrowRenderer();

  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static final _dotPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      throw StateError(
        'ArrowRenderer can only render ArrowData (got ${data.runtimeType})',
      );
    }

    final strokeOpacity = (data.color.a * element.opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 || data.strokeWidth <= 0) {
      return;
    }

    final cached = arrowVisualCache.resolve(element: element, data: data);
    if (cached.geometry.localPoints.length < 2) {
      return;
    }

    final rect = element.rect;
    final strokeColor = Color(
      data.color.withValues(alpha: strokeOpacity).toARGB32(),
    );

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    final strokePaint = _strokePaint
      ..strokeWidth = data.strokeWidth
      ..color = strokeColor;

    switch (data.strokeStyle) {
      case StrokeStyle.dotted:
        final dotPositions = cached.dotPositions;
        if (dotPositions != null && dotPositions.isNotEmpty) {
          final dotPaint = _dotPaint
            ..strokeWidth = cached.dotRadius * 2
            ..color = strokeColor;
          canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
        }
        for (final arrowheadPath in cached.arrowheadPaths) {
          canvas.drawPath(arrowheadPath, strokePaint);
        }
      case StrokeStyle.solid || StrokeStyle.dashed:
        final combinedPath = cached.combinedStrokePath;
        if (combinedPath != null) {
          canvas.drawPath(combinedPath, strokePaint);
        }
    }

    canvas.restore();
  }
}
