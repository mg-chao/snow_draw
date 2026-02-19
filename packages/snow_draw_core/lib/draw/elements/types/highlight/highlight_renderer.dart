import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'highlight_data.dart';

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

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.strokeColor.a * opacity).clamp(0.0, 1.0);

    canvas.save();
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    final shapeRect = Rect.fromLTWH(0, 0, rect.width, rect.height);

    if (fillOpacity > 0) {
      final fillPaint = _fillPaint
        ..color = data.color.withValues(alpha: fillOpacity);
      if (data.shape == HighlightShape.rectangle) {
        canvas.drawRect(shapeRect, fillPaint);
      } else {
        canvas.drawOval(shapeRect, fillPaint);
      }
    }

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      final strokePaint = _strokePaint
        ..strokeWidth = data.strokeWidth
        ..color = data.strokeColor.withValues(alpha: strokeOpacity);
      if (data.shape == HighlightShape.rectangle) {
        canvas.drawRect(shapeRect, strokePaint);
      } else {
        canvas.drawOval(shapeRect, strokePaint);
      }
    }

    canvas.restore();
  }
}
