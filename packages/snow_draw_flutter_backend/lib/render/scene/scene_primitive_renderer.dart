import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import '../../services/text/flutter_text_layout.dart';
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
  static final _multiplyLayerPaint = Paint()..blendMode = BlendMode.multiply;
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
      case RenderTransformPrimitive():
        _renderTransform(canvas, primitive, locale: locale);
      case RenderBlendMultiplyGroupPrimitive():
        _renderBlendMultiplyGroup(canvas, primitive, locale: locale);
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
    final maxWidth = _resolveTextLayoutWidth(primitive.maxWidth);
    final textOffset = Offset(primitive.origin.x, primitive.origin.y);
    final textData = TextData(
      text: text,
      color: DrawColor(primitive.colorArgb),
      fontSize: primitive.fontSize,
      fontFamily: primitive.fontFamily,
      horizontalAlign: _toCoreTextAlign(primitive.align),
      verticalAlign: TextVerticalAlign.top,
    );

    final strokeColorArgb = primitive.strokeColorArgb;
    if (strokeColorArgb != null && primitive.strokeWidth > 0) {
      final strokePaint = _textStrokePaint
        ..strokeWidth = primitive.strokeWidth
        ..color = Color(strokeColorArgb);
      final strokeStyle = buildTextStyle(
        data: textData,
        locale: locale,
      ).copyWith(foreground: strokePaint);
      final strokeLayout = layoutText(
        data: textData,
        maxWidth: maxWidth,
        styleOverride: strokeStyle,
        locale: locale,
      );
      canvas.drawParagraph(strokeLayout.paragraph, textOffset);
    }

    final fillLayout = layoutText(
      data: textData,
      maxWidth: maxWidth,
      locale: locale,
    );
    canvas.drawParagraph(fillLayout.paragraph, textOffset);
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

  void _renderBlendMultiplyGroup(
    Canvas canvas,
    RenderBlendMultiplyGroupPrimitive primitive, {
    Locale? locale,
  }) {
    final layerBounds = _resolveSceneCullRect(primitive.child);
    if (layerBounds != null && _isSceneOutsideClipBounds(canvas, layerBounds)) {
      return;
    }
    canvas.saveLayer(layerBounds, _multiplyLayerPaint);
    renderScene(canvas: canvas, scene: primitive.child, locale: locale);
    canvas.restore();
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

  double _resolveTextLayoutWidth(double maxWidth) {
    if (maxWidth.isFinite && maxWidth > 0) {
      return maxWidth;
    }
    if (maxWidth == 0 || maxWidth.isNaN) {
      return 1;
    }
    return _unboundedTextLayoutWidth;
  }

  TextHorizontalAlign _toCoreTextAlign(RenderTextAlign align) {
    switch (align) {
      case RenderTextAlign.left:
        return TextHorizontalAlign.left;
      case RenderTextAlign.center:
        return TextHorizontalAlign.center;
      case RenderTextAlign.right:
        return TextHorizontalAlign.right;
    }
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
      case RenderBlendMultiplyGroupPrimitive():
        return _resolveSceneOutset(primitive.child);
      case RenderPathFillPrimitive():
      case RenderHatchPathFillPrimitive():
        return 0;
    }
  }
}
