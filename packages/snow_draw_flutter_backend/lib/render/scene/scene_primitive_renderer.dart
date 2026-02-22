import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import '../patterns/stroke_pattern_utils.dart';

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
  static const _unboundedTextLayoutWidth = 1000000.0;

  void renderScene({
    required Canvas canvas,
    required RenderScene scene,
    Locale? locale,
  }) {
    final cullRect = _resolveSceneCullRect(scene);
    if (cullRect != null && _isSceneOutsideClipBounds(canvas, cullRect)) {
      return;
    }
    for (final primitive in scene.primitives) {
      _renderPrimitive(canvas: canvas, primitive: primitive, locale: locale);
    }
  }

  void _renderPrimitive({
    required Canvas canvas,
    required RenderPrimitive primitive,
    Locale? locale,
  }) {
    switch (primitive) {
      case RenderPathStrokePrimitive():
        _renderPathStroke(canvas, primitive);
      case RenderPathFillPrimitive():
        _renderPathFill(canvas, primitive);
      case RenderHatchPathFillPrimitive():
        _renderHatchPathFill(canvas, primitive);
      case RenderTextRunPrimitive():
        _renderTextRun(canvas, primitive, locale: locale);
      case RenderClipRectPrimitive():
        _renderClipRect(canvas, primitive, locale: locale);
      case RenderTransformPrimitive():
        _renderTransform(canvas, primitive, locale: locale);
      case RenderFilterGroupPrimitive():
        _renderFilterGroup(canvas, primitive, locale: locale);
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
    canvas.drawPath(buildDashPatternPath(path, dashPattern), paint);
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

  void _renderTextRun(
    Canvas canvas,
    RenderTextRunPrimitive primitive, {
    Locale? locale,
  }) {
    final text = primitive.text.isEmpty ? ' ' : primitive.text;
    final fontFamily = _sanitizeFontFamily(primitive.fontFamily);
    final maxWidth = _resolveTextLayoutWidth(primitive.maxWidth);
    final textOffset = Offset(primitive.origin.x, primitive.origin.y);
    final strokeColorArgb = primitive.strokeColorArgb;
    if (strokeColorArgb != null && primitive.strokeWidth > 0) {
      final strokePaint = _textStrokePaint
        ..strokeWidth = primitive.strokeWidth
        ..color = Color(strokeColorArgb);
      final strokeParagraph = _buildTextParagraph(
        text: text,
        fontSize: primitive.fontSize,
        fontFamily: fontFamily,
        align: primitive.align,
        maxWidth: maxWidth,
        locale: locale,
        foreground: strokePaint,
      );
      canvas.drawParagraph(strokeParagraph, textOffset);
    }

    final fillParagraph = _buildTextParagraph(
      text: text,
      fontSize: primitive.fontSize,
      fontFamily: fontFamily,
      align: primitive.align,
      maxWidth: maxWidth,
      locale: locale,
      color: Color(primitive.colorArgb),
    );
    canvas.drawParagraph(fillParagraph, textOffset);
  }

  void _renderClipRect(
    Canvas canvas,
    RenderClipRectPrimitive primitive, {
    Locale? locale,
  }) {
    canvas
      ..save()
      ..clipRect(_toRect(primitive.clipRect));
    renderScene(canvas: canvas, scene: primitive.child, locale: locale);
    canvas.restore();
  }

  void _renderTransform(
    Canvas canvas,
    RenderTransformPrimitive primitive, {
    Locale? locale,
  }) {
    canvas
      ..save()
      ..translate(primitive.translate.x, primitive.translate.y);
    if (primitive.rotation != 0) {
      canvas.rotate(primitive.rotation);
    }
    canvas.scale(primitive.scaleX, primitive.scaleY);
    renderScene(canvas: canvas, scene: primitive.child, locale: locale);
    canvas.restore();
  }

  void _renderFilterGroup(
    Canvas canvas,
    RenderFilterGroupPrimitive primitive, {
    Locale? locale,
  }) {
    final opacity = primitive.parameters['opacity'];
    if (primitive.filterType == 'opacity' && opacity != null) {
      final alpha = (opacity.clamp(0, 1) * 255).round();
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB(alpha, 255, 255, 255),
      );
      renderScene(canvas: canvas, scene: primitive.child, locale: locale);
      canvas.restore();
      return;
    }
    if (primitive.filterType == 'blend_multiply') {
      canvas.saveLayer(null, Paint()..blendMode = BlendMode.multiply);
      renderScene(canvas: canvas, scene: primitive.child, locale: locale);
      canvas.restore();
      return;
    }
    renderScene(canvas: canvas, scene: primitive.child, locale: locale);
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

  ui.Paragraph _buildTextParagraph({
    required String text,
    required double fontSize,
    required String? fontFamily,
    required RenderTextAlign align,
    required double maxWidth,
    Locale? locale,
    Color? color,
    Paint? foreground,
  }) {
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: _toTextAlign(align),
      textDirection: ui.TextDirection.ltr,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textHeightBehavior: _textHeightBehavior,
      strutStyle: ui.StrutStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        forceStrutHeight: true,
      ),
      locale: locale,
    );

    final textStyle = foreground != null
        ? ui.TextStyle(
            fontSize: fontSize,
            fontFamily: fontFamily,
            foreground: foreground,
            locale: locale,
            textBaseline: ui.TextBaseline.alphabetic,
          )
        : ui.TextStyle(
            color: color,
            fontSize: fontSize,
            fontFamily: fontFamily,
            locale: locale,
            textBaseline: ui.TextBaseline.alphabetic,
          );

    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(text)
      ..pop();

    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  double _resolveTextLayoutWidth(double maxWidth) {
    if (maxWidth.isFinite && maxWidth > 0) {
      return maxWidth;
    }
    if (maxWidth == 0 || maxWidth.isNaN) {
      return 1;
    }
    return _unboundedTextLayoutWidth;
  }

  String? _sanitizeFontFamily(String? fontFamily) {
    final trimmed = fontFamily?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Rect? _resolveSceneCullRect(RenderScene scene) {
    final bounds = scene.cullRect;
    if (bounds == null) {
      return null;
    }
    final outset = _resolveSceneOutset(scene);
    final resolvedOutset = outset.isFinite && outset > 0 ? outset : 0.0;
    final rect = _toRect(bounds);
    return Rect.fromLTRB(
      rect.left - resolvedOutset,
      rect.top - resolvedOutset,
      rect.right + resolvedOutset,
      rect.bottom + resolvedOutset,
    );
  }

  bool _isSceneOutsideClipBounds(Canvas canvas, Rect cullRect) {
    final clipBounds = canvas.getLocalClipBounds();
    if (!clipBounds.isFinite) {
      return false;
    }
    return !clipBounds.overlaps(cullRect);
  }

  double _resolveSceneOutset(RenderScene scene) {
    var maxOutset = 0.0;
    for (final primitive in scene.primitives) {
      final primitiveOutset = _resolvePrimitiveOutset(primitive);
      if (primitiveOutset > maxOutset) {
        maxOutset = primitiveOutset;
      }
    }
    return maxOutset;
  }

  double _resolvePrimitiveOutset(RenderPrimitive primitive) {
    switch (primitive) {
      case RenderPathStrokePrimitive():
        return primitive.strokeWidth / 2;
      case RenderTextRunPrimitive():
        return primitive.strokeWidth > 0 ? primitive.strokeWidth / 2 : 0;
      case RenderClipRectPrimitive():
        return _resolveSceneOutset(primitive.child);
      case RenderTransformPrimitive():
        final childOutset = _resolveSceneOutset(primitive.child);
        final maxScale = math.max(
          primitive.scaleX.abs(),
          primitive.scaleY.abs(),
        );
        if (!maxScale.isFinite || maxScale <= 0) {
          return childOutset;
        }
        return childOutset * maxScale;
      case RenderFilterGroupPrimitive():
        return _resolveSceneOutset(primitive.child);
      case RenderPathFillPrimitive():
      case RenderHatchPathFillPrimitive():
      case RenderImageHandlePrimitive():
      case RenderPictureHandlePrimitive():
        return 0;
    }
  }
}
