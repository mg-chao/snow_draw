import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'arrow_data.dart';
import 'arrow_visual_cache.dart';

class ArrowRenderer extends ElementTypeRenderer {
  const ArrowRenderer();

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

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 || data.strokeWidth <= 0) {
      return;
    }

    final cached = arrowVisualCache.resolve(element: element, data: data);
    if (cached.geometry.localPoints.length < 2) {
      return;
    }

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = data.color.withValues(alpha: strokeOpacity)
      ..isAntiAlias = true;

    if (data.strokeStyle == StrokeStyle.dotted) {
      final dottedPath = cached.dottedShaftPath;
      if (dottedPath != null) {
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = strokePaint.color
          ..isAntiAlias = true;
        canvas.drawPath(dottedPath, dotPaint);
      }

      for (final arrowheadPath in cached.arrowheadPaths) {
        canvas.drawPath(arrowheadPath, strokePaint);
      }
    } else {
      final combinedPath = cached.combinedStrokePath;
      if (combinedPath != null) {
        canvas.drawPath(combinedPath, strokePaint);
      }
    }

    canvas.restore();
  }
}
