import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:snow_draw_core/draw/render/scene/render_scene.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

/// Paints backend-agnostic [RenderScene] primitives to a Flutter [Canvas].
class ScenePrimitiveRenderer {
  const ScenePrimitiveRenderer();

  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  static final _textStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static const _textHeightBehavior = TextHeightBehavior();
  static const TextScaler _textScaler = TextScaler.noScaling;

  void renderScene({required Canvas canvas, required RenderScene scene}) {
    for (final primitive in scene.primitives) {
      _renderPrimitive(canvas: canvas, primitive: primitive);
    }
  }

  void _renderPrimitive({
    required Canvas canvas,
    required RenderPrimitive primitive,
  }) {
    switch (primitive) {
      case RenderPathStrokePrimitive():
        _renderPathStroke(canvas, primitive);
      case RenderPathFillPrimitive():
        _renderPathFill(canvas, primitive);
      case RenderHatchPathFillPrimitive():
        _renderHatchPathFill(canvas, primitive);
      case RenderTextRunPrimitive():
        _renderTextRun(canvas, primitive);
      case RenderClipRectPrimitive():
        _renderClipRect(canvas, primitive);
      case RenderTransformPrimitive():
        _renderTransform(canvas, primitive);
      case RenderFilterGroupPrimitive():
        _renderFilterGroup(canvas, primitive);
      case RenderImageHandlePrimitive():
        _renderImagePlaceholder(canvas, primitive);
      case RenderPictureHandlePrimitive():
        _renderPicturePlaceholder(canvas, primitive);
    }
  }

  void _renderPathStroke(Canvas canvas, RenderPathStrokePrimitive primitive) {
    final path = _toFlutterPath(primitive.path);
    if (path == null) {
      return;
    }
    final paint = _strokePaint
      ..color = Color(primitive.colorArgb)
      ..strokeWidth = primitive.strokeWidth
      ..strokeCap = _toStrokeCap(primitive.strokeCap)
      ..strokeJoin = _toStrokeJoin(primitive.strokeJoin);
    final dashPattern = primitive.dashPattern;
    if (dashPattern == null || dashPattern.isEmpty) {
      canvas.drawPath(path, paint);
      return;
    }
    _drawDashedPath(
      canvas: canvas,
      path: path,
      paint: paint,
      dashPattern: dashPattern,
    );
  }

  void _renderPathFill(Canvas canvas, RenderPathFillPrimitive primitive) {
    final path = _toFlutterPath(primitive.path);
    if (path == null) {
      return;
    }
    final paint = _fillPaint..color = Color(primitive.colorArgb);
    canvas.drawPath(path, paint);
  }

  void _renderHatchPathFill(
    Canvas canvas,
    RenderHatchPathFillPrimitive primitive,
  ) {
    final path = _toFlutterPath(primitive.path);
    if (path == null) {
      return;
    }
    final spacing = primitive.spacing;
    final lineWidth = primitive.lineWidth;
    if (!spacing.isFinite ||
        spacing <= 0 ||
        !lineWidth.isFinite ||
        lineWidth <= 0) {
      return;
    }

    final paint = _strokePaint
      ..color = Color(primitive.colorArgb)
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;

    canvas
      ..save()
      ..clipPath(path);
    _drawHatchLines(
      canvas: canvas,
      bounds: _toRect(primitive.clipBounds),
      angleRadians: primitive.angleRadians,
      spacing: spacing,
      paint: paint,
    );
    if (primitive.pattern == RenderHatchPattern.crossLine) {
      _drawHatchLines(
        canvas: canvas,
        bounds: _toRect(primitive.clipBounds),
        angleRadians: primitive.angleRadians + math.pi / 2,
        spacing: spacing,
        paint: paint,
      );
    }
    canvas.restore();
  }

  void _renderTextRun(Canvas canvas, RenderTextRunPrimitive primitive) {
    final textOffset = Offset(primitive.origin.x, primitive.origin.y);
    final strokeColorArgb = primitive.strokeColorArgb;
    if (strokeColorArgb != null && primitive.strokeWidth > 0) {
      final strokePaint = _textStrokePaint
        ..strokeWidth = primitive.strokeWidth
        ..color = Color(strokeColorArgb);
      final strokeTextStyle = TextStyle(
        fontSize: primitive.fontSize,
        fontFamily: primitive.fontFamily,
        textBaseline: TextBaseline.alphabetic,
        foreground: strokePaint,
      );
      TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: _toTextAlign(primitive.align),
          textHeightBehavior: _textHeightBehavior,
          textScaler: _textScaler,
          strutStyle: StrutStyle.fromTextStyle(
            strokeTextStyle,
            forceStrutHeight: true,
          ),
          text: TextSpan(text: primitive.text, style: strokeTextStyle),
        )
        ..layout(maxWidth: primitive.maxWidth)
        ..paint(canvas, textOffset);
    }

    final fillTextStyle = TextStyle(
      color: Color(primitive.colorArgb),
      fontSize: primitive.fontSize,
      fontFamily: primitive.fontFamily,
      textBaseline: TextBaseline.alphabetic,
    );
    TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: _toTextAlign(primitive.align),
        textHeightBehavior: _textHeightBehavior,
        textScaler: _textScaler,
        strutStyle: StrutStyle.fromTextStyle(
          fillTextStyle,
          forceStrutHeight: true,
        ),
        text: TextSpan(text: primitive.text, style: fillTextStyle),
      )
      ..layout(maxWidth: primitive.maxWidth)
      ..paint(canvas, textOffset);
  }

  void _renderClipRect(Canvas canvas, RenderClipRectPrimitive primitive) {
    canvas
      ..save()
      ..clipRect(_toRect(primitive.clipRect));
    renderScene(canvas: canvas, scene: primitive.child);
    canvas.restore();
  }

  void _renderTransform(Canvas canvas, RenderTransformPrimitive primitive) {
    canvas
      ..save()
      ..translate(primitive.translate.x, primitive.translate.y);
    if (primitive.rotation != 0) {
      canvas.rotate(primitive.rotation);
    }
    canvas.scale(primitive.scaleX, primitive.scaleY);
    renderScene(canvas: canvas, scene: primitive.child);
    canvas.restore();
  }

  void _renderFilterGroup(Canvas canvas, RenderFilterGroupPrimitive primitive) {
    final opacity = primitive.parameters['opacity'];
    if (primitive.filterType == 'opacity' && opacity != null) {
      final alpha = (opacity.clamp(0, 1) * 255).round();
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB(alpha, 255, 255, 255),
      );
      renderScene(canvas: canvas, scene: primitive.child);
      canvas.restore();
      return;
    }
    if (primitive.filterType == 'blend_multiply') {
      canvas.saveLayer(null, Paint()..blendMode = BlendMode.multiply);
      renderScene(canvas: canvas, scene: primitive.child);
      canvas.restore();
      return;
    }
    renderScene(canvas: canvas, scene: primitive.child);
  }

  void _renderImagePlaceholder(
    Canvas canvas,
    RenderImageHandlePrimitive primitive,
  ) {
    final rect = _toRect(primitive.destinationRect);
    final stroke = _strokePaint
      ..color = const Color(0x55FF00FF)
      ..strokeWidth = 1;
    canvas
      ..drawRect(rect, stroke)
      ..drawLine(rect.topLeft, rect.bottomRight, stroke)
      ..drawLine(rect.topRight, rect.bottomLeft, stroke);
  }

  void _renderPicturePlaceholder(
    Canvas canvas,
    RenderPictureHandlePrimitive primitive,
  ) {
    final paint = _fillPaint..color = const Color(0x22000000);
    canvas.drawCircle(Offset.zero, 2, paint);
  }

  Path? _toFlutterPath(RenderPath path) {
    if (path.commands.isEmpty) {
      return null;
    }
    final resolved = Path();
    for (final command in path.commands) {
      switch (command) {
        case RenderMoveTo():
          resolved.moveTo(command.point.x, command.point.y);
        case RenderLineTo():
          resolved.lineTo(command.point.x, command.point.y);
        case RenderQuadraticTo():
          resolved.quadraticBezierTo(
            command.control.x,
            command.control.y,
            command.end.x,
            command.end.y,
          );
        case RenderCubicTo():
          resolved.cubicTo(
            command.control1.x,
            command.control1.y,
            command.control2.x,
            command.control2.y,
            command.end.x,
            command.end.y,
          );
        case RenderClosePath():
          resolved.close();
      }
    }
    return resolved;
  }

  StrokeCap _toStrokeCap(RenderStrokeCap strokeCap) {
    switch (strokeCap) {
      case RenderStrokeCap.butt:
        return StrokeCap.butt;
      case RenderStrokeCap.round:
        return StrokeCap.round;
      case RenderStrokeCap.square:
        return StrokeCap.square;
    }
  }

  StrokeJoin _toStrokeJoin(RenderStrokeJoin strokeJoin) {
    switch (strokeJoin) {
      case RenderStrokeJoin.miter:
        return StrokeJoin.miter;
      case RenderStrokeJoin.round:
        return StrokeJoin.round;
      case RenderStrokeJoin.bevel:
        return StrokeJoin.bevel;
    }
  }

  TextAlign _toTextAlign(RenderTextAlign align) {
    switch (align) {
      case RenderTextAlign.left:
        return TextAlign.left;
      case RenderTextAlign.center:
        return TextAlign.center;
      case RenderTextAlign.right:
        return TextAlign.right;
    }
  }

  Rect _toRect(DrawRect rect) =>
      Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height);

  void _drawDashedPath({
    required Canvas canvas,
    required Path path,
    required Paint paint,
    required List<double> dashPattern,
  }) {
    final normalized = dashPattern.where((value) => value > 0).toList();
    if (normalized.isEmpty) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var patternIndex = 0;
      var drawSegment = true;
      while (distance < metric.length) {
        final segmentLength = normalized[patternIndex % normalized.length];
        final end = math.min(distance + segmentLength, metric.length);
        if (drawSegment) {
          final segment = metric.extractPath(distance, end);
          canvas.drawPath(segment, paint);
        }
        distance = end;
        patternIndex += 1;
        drawSegment = !drawSegment;
      }
    }
  }

  void _drawHatchLines({
    required Canvas canvas,
    required Rect bounds,
    required double angleRadians,
    required double spacing,
    required Paint paint,
  }) {
    if (bounds.width <= 0 || bounds.height <= 0) {
      return;
    }
    final center = bounds.center;
    final directionX = math.cos(angleRadians);
    final directionY = math.sin(angleRadians);
    final normalX = -directionY;
    final normalY = directionX;
    final halfDiagonal =
        math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height) /
            2 +
        spacing;
    if (!halfDiagonal.isFinite || halfDiagonal <= 0) {
      return;
    }

    final lineCount = ((halfDiagonal * 2) / spacing).ceil();
    for (var index = 0; index <= lineCount; index += 1) {
      final offset = -halfDiagonal + index * spacing;
      final baseX = center.dx + normalX * offset;
      final baseY = center.dy + normalY * offset;
      final start = Offset(
        baseX - directionX * halfDiagonal,
        baseY - directionY * halfDiagonal,
      );
      final end = Offset(
        baseX + directionX * halfDiagonal,
        baseY + directionY * halfDiagonal,
      );
      canvas.drawLine(start, end, paint);
    }
  }
}
