import 'dart:ui';

import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'element_type_renderer.dart';

class HighlightRenderer extends ElementTypeRenderer {
  const HighlightRenderer();

  static final _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.multiply
    ..isAntiAlias = true;

  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! HighlightData) {
      throw StateError(
        'HighlightRenderer can only render HighlightData (got '
        '${data.runtimeType})',
      );
    }

    final fillOpacity = (data.color.a * element.opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.strokeColor.a * element.opacity).clamp(
      0.0,
      1.0,
    );
    final shouldPaintFill = fillOpacity > 0;
    final shouldPaintStroke = strokeOpacity > 0 && data.strokeWidth > 0;
    if (!shouldPaintFill && !shouldPaintStroke) {
      return;
    }

    final rect = element.rect;
    final shapeRect = Rect.fromLTWH(0, 0, rect.width, rect.height);

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    if (shouldPaintFill) {
      _drawShape(
        canvas: canvas,
        shape: data.shape,
        rect: shapeRect,
        paint: _fillPaint
          ..color = Color(data.color.withValues(alpha: fillOpacity).toARGB32()),
      );
    }

    if (shouldPaintStroke) {
      _drawShape(
        canvas: canvas,
        shape: data.shape,
        rect: shapeRect,
        paint: _strokePaint
          ..strokeWidth = data.strokeWidth
          ..color = Color(
            data.strokeColor.withValues(alpha: strokeOpacity).toARGB32(),
          ),
      );
    }

    canvas.restore();
  }

  static void _drawShape({
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
}
