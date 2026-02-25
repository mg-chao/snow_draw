import 'dart:math' as math;
import 'dart:ui';

import 'package:snow_draw_core/snow_draw_engine.dart';

import '../free_draw/free_draw_visual_cache.dart';
import '../geometry/arrow_geometry.dart';
import '../patterns/stroke_pattern_utils.dart';
import '../text/text_renderer.dart';

/// Executes engine-owned render tasks on Flutter canvas primitives.
class FlutterRenderTaskExecutor {
  const FlutterRenderTaskExecutor();

  static const double _hatchAngle = -math.pi / 4;
  static const double _crossHatchAngle = _hatchAngle + (math.pi / 2);
  static const _textRenderer = TextRenderer();

  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  /// Executes [tasks] in order.
  void executeTasks({
    required Canvas canvas,
    required List<RenderTask> tasks,
    Locale? locale,
  }) {
    for (final task in tasks) {
      _executeTask(canvas: canvas, task: task, locale: locale);
    }
  }

  void _executeTask({
    required Canvas canvas,
    required RenderTask task,
    Locale? locale,
  }) {
    switch (task) {
      case RectangleRenderTask():
        _renderRectangle(canvas: canvas, task: task);
      case LineRenderTask():
        _renderLine(canvas: canvas, task: task);
      case ArrowRenderTask():
        _renderArrow(canvas: canvas, task: task);
      case FreeDrawRenderTask():
        _renderFreeDraw(canvas: canvas, task: task);
      case TextRenderTask():
        _renderText(canvas: canvas, task: task, locale: locale);
      case SerialNumberRenderTask():
        _renderSerialNumber(canvas: canvas, task: task, locale: locale);
      case HighlightRenderTask():
        _renderHighlight(canvas: canvas, task: task);
      case FilterRenderTask():
        // Filter elements are composed by dedicated filter segment renderers.
        return;
      case _:
        // Overlay/background tasks are handled by dedicated backend painters.
        return;
    }
  }

  void _renderRectangle({
    required Canvas canvas,
    required RectangleRenderTask task,
  }) {
    final element = task.element;
    final data = task.data;
    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }

    final drawRect = Rect.fromLTWH(
      rect.minX,
      rect.minY,
      rect.width,
      rect.height,
    );
    final radius = _resolveCornerRadius(
      cornerRadius: data.cornerRadius,
      width: rect.width,
      height: rect.height,
    );
    final rrect = RRect.fromRectAndRadius(drawRect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    final fillColor = _withOpacity(data.fillColor, element.opacity);
    final strokeColor = _withOpacity(data.color, element.opacity);
    final fillVisible = _isVisibleColor(fillColor);
    final strokeVisible = _isVisibleColor(strokeColor) && data.strokeWidth > 0;
    if (!fillVisible && !strokeVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);

    if (fillVisible) {
      _fillPathWithStyle(
        canvas: canvas,
        path: path,
        bounds: drawRect,
        color: fillColor,
        fillStyle: data.fillStyle,
        referenceStrokeWidth: data.strokeWidth,
      );
    }

    if (strokeVisible) {
      _drawPathStroke(
        canvas: canvas,
        path: path,
        color: strokeColor,
        strokeWidth: data.strokeWidth,
        strokeStyle: data.strokeStyle,
        strokeCap: data.strokeStyle == StrokeStyle.solid
            ? StrokeCap.butt
            : StrokeCap.round,
        strokeJoin: StrokeJoin.miter,
      );
    }

    canvas.restore();
  }

  void _renderLine({required Canvas canvas, required LineRenderTask task}) {
    final element = task.element;
    final data = task.data;
    final points = FlutterArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
    if (points.length < 2) {
      return;
    }

    final path = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
      points: points,
      arrowType: data.arrowType,
    );
    final strokeColor = _withOpacity(data.color, element.opacity);
    final fillColor = _withOpacity(data.fillColor, element.opacity);
    final strokeVisible = _isVisibleColor(strokeColor) && data.strokeWidth > 0;
    final isClosed =
        data.points.length > 2 && data.points.first == data.points.last;
    final fillVisible = _isVisibleColor(fillColor) && isClosed;
    if (!strokeVisible && !fillVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);

    if (fillVisible) {
      final fillPath = Path.from(path)..close();
      _fillPathWithStyle(
        canvas: canvas,
        path: fillPath,
        bounds: fillPath.getBounds(),
        color: fillColor,
        fillStyle: data.fillStyle,
        referenceStrokeWidth: data.strokeWidth,
      );
    }

    if (strokeVisible) {
      _drawPathStroke(
        canvas: canvas,
        path: path,
        color: strokeColor,
        strokeWidth: data.strokeWidth,
        strokeStyle: data.strokeStyle,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );
    }

    canvas.restore();
  }

  void _renderArrow({required Canvas canvas, required ArrowRenderTask task}) {
    final element = task.element;
    final data = task.data;
    final descriptor = FlutterArrowGeometryDescriptor(
      data: data,
      rect: element.rect,
    );
    if (descriptor.insetPoints.length < 2) {
      return;
    }

    final worldInsetPoints = <Offset>[
      for (final point in descriptor.insetPoints)
        Offset(element.rect.minX + point.dx, element.rect.minY + point.dy),
    ];
    final shaftPath = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
      points: worldInsetPoints,
      arrowType: data.arrowType,
    );

    final arrowheadsPath = Path();
    final startDirection = descriptor.startDirection;
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      arrowheadsPath.addPath(
        FlutterArrowGeometry.buildArrowheadPath(
          tip: worldInsetPoints.first,
          direction: startDirection,
          style: data.startArrowhead,
          strokeWidth: data.strokeWidth,
        ),
        Offset.zero,
      );
    }
    final endDirection = descriptor.endDirection;
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      arrowheadsPath.addPath(
        FlutterArrowGeometry.buildArrowheadPath(
          tip: worldInsetPoints.last,
          direction: endDirection,
          style: data.endArrowhead,
          strokeWidth: data.strokeWidth,
        ),
        Offset.zero,
      );
    }

    final strokeColor = _withOpacity(data.color, element.opacity);
    final strokeVisible = _isVisibleColor(strokeColor) && data.strokeWidth > 0;
    if (!strokeVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);

    _drawPathStroke(
      canvas: canvas,
      path: shaftPath,
      color: strokeColor,
      strokeWidth: data.strokeWidth,
      strokeStyle: data.strokeStyle,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    );

    if (!arrowheadsPath.getBounds().isEmpty) {
      final paint = _strokePaint
        ..color = strokeColor
        ..strokeWidth = data.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(arrowheadsPath, paint);
    }

    canvas.restore();
  }

  void _renderFreeDraw({
    required Canvas canvas,
    required FreeDrawRenderTask task,
  }) {
    final element = task.element;
    final data = task.data;
    final visualEntry = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );
    if (visualEntry.pointCount < 2) {
      return;
    }
    final path = visualEntry.path;

    final strokeColor = _withOpacity(data.color, element.opacity);
    final fillColor = _withOpacity(data.fillColor, element.opacity);
    final strokeVisible = _isVisibleColor(strokeColor) && data.strokeWidth > 0;
    final fillVisible =
        _isVisibleColor(fillColor) &&
        _isFreeDrawClosed(data: data, rect: element.rect);
    if (!strokeVisible && !fillVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);
    canvas.translate(element.rect.minX, element.rect.minY);

    if (fillVisible) {
      final fillPath = Path.from(path)..close();
      _fillPathWithStyle(
        canvas: canvas,
        path: fillPath,
        bounds: fillPath.getBounds(),
        color: fillColor,
        fillStyle: data.fillStyle,
        referenceStrokeWidth: data.strokeWidth,
      );
    }

    if (strokeVisible) {
      _drawPathStroke(
        canvas: canvas,
        path: path,
        color: strokeColor,
        strokeWidth: data.strokeWidth,
        strokeStyle: data.strokeStyle,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );
    }

    canvas.restore();
  }

  void _renderText({
    required Canvas canvas,
    required TextRenderTask task,
    required Locale? locale,
  }) {
    _textRenderer.render(
      canvas: canvas,
      element: task.element,
      scaleFactor: 1,
      locale: _resolveLocale(locale: locale, localeTag: task.localeTag),
    );
  }

  void _renderSerialNumber({
    required Canvas canvas,
    required SerialNumberRenderTask task,
    required Locale? locale,
  }) {
    final element = task.element;
    final data = task.data;
    final rect = element.rect;
    final diameter = math.min(rect.width, rect.height);
    if (diameter <= 0 || !diameter.isFinite) {
      return;
    }

    final radius = diameter / 2;
    final circleRect = Rect.fromCircle(
      center: Offset(rect.centerX, rect.centerY),
      radius: radius,
    );
    final circlePath = Path()..addOval(circleRect);

    final fillColor = _withOpacity(data.fillColor, element.opacity);
    final strokeColor = _withOpacity(data.color, element.opacity);
    final strokeWidth = _resolveSerialStrokeWidth(data: data);
    final fillVisible = _isVisibleColor(fillColor);
    final strokeVisible = _isVisibleColor(strokeColor) && strokeWidth > 0;
    if (!fillVisible && !strokeVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);

    if (fillVisible) {
      _fillPathWithStyle(
        canvas: canvas,
        path: circlePath,
        bounds: circleRect,
        color: fillColor,
        fillStyle: data.fillStyle,
        referenceStrokeWidth: strokeWidth,
      );
    }

    if (strokeVisible) {
      _drawPathStroke(
        canvas: canvas,
        path: circlePath,
        color: strokeColor,
        strokeWidth: strokeWidth,
        strokeStyle: data.strokeStyle,
        strokeCap: data.strokeStyle == StrokeStyle.solid
            ? StrokeCap.butt
            : StrokeCap.round,
        strokeJoin: StrokeJoin.miter,
      );
    }

    canvas.restore();

    final textColor = _withOpacity(data.color, element.opacity);
    if (!_isVisibleColor(textColor)) {
      return;
    }

    final textData = TextData(
      text: data.number.toString(),
      color: data.color,
      fontSize: data.fontSize,
      fontFamily: data.fontFamily,
      horizontalAlign: TextHorizontalAlign.center,
      autoResize: false,
    );
    final textElement = element.copyWith(
      rect: circleRect.toDrawRect(),
      data: textData,
    );
    _textRenderer.render(
      canvas: canvas,
      element: textElement,
      scaleFactor: 1,
      locale: _resolveLocale(locale: locale, localeTag: task.localeTag),
    );
  }

  void _renderHighlight({
    required Canvas canvas,
    required HighlightRenderTask task,
  }) {
    final element = task.element;
    final data = task.data;
    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }

    final shapeRect = Rect.fromLTWH(
      rect.minX,
      rect.minY,
      rect.width,
      rect.height,
    );
    final shapePath = Path();
    if (data.shape == HighlightShape.ellipse) {
      shapePath.addOval(shapeRect);
    } else {
      shapePath.addRect(shapeRect);
    }

    final fillColor = _withOpacity(data.color, element.opacity);
    final strokeColor = _withOpacity(data.strokeColor, element.opacity);
    final fillVisible = _isVisibleColor(fillColor);
    final strokeVisible = _isVisibleColor(strokeColor) && data.strokeWidth > 0;
    if (!fillVisible && !strokeVisible) {
      return;
    }

    canvas.save();
    _applyElementRotation(canvas, element);

    if (fillVisible) {
      final paint = _fillPaint
        ..blendMode = BlendMode.multiply
        ..color = fillColor;
      canvas.drawPath(shapePath, paint);
      paint.blendMode = BlendMode.srcOver;
    }

    if (strokeVisible) {
      final paint = _strokePaint
        ..color = strokeColor
        ..strokeWidth = data.strokeWidth
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.miter;
      canvas.drawPath(shapePath, paint);
    }

    canvas.restore();
  }

  void _applyElementRotation(Canvas canvas, ElementState element) {
    if (element.rotation == 0) {
      return;
    }
    final center = element.rect.center;
    canvas
      ..translate(center.x, center.y)
      ..rotate(element.rotation)
      ..translate(-center.x, -center.y);
  }

  void _fillPathWithStyle({
    required Canvas canvas,
    required Path path,
    required Rect bounds,
    required Color color,
    required FillStyle fillStyle,
    required double referenceStrokeWidth,
  }) {
    if (fillStyle == FillStyle.solid) {
      final paint = _fillPaint..color = color;
      canvas.drawPath(path, paint);
      return;
    }

    final hatch = _resolveHatch(strokeWidth: referenceStrokeWidth);
    final paint = buildLineFillPaint(
      spacing: hatch.spacing,
      lineWidth: hatch.lineWidth,
      angle: _hatchAngle,
      color: color,
    );
    canvas
      ..save()
      ..clipPath(path)
      ..drawRect(bounds, paint);
    if (fillStyle == FillStyle.crossLine) {
      final crossPaint = buildLineFillPaint(
        spacing: hatch.spacing,
        lineWidth: hatch.lineWidth,
        angle: _crossHatchAngle,
        color: color,
      );
      canvas.drawRect(bounds, crossPaint);
    }
    canvas.restore();
  }

  void _drawPathStroke({
    required Canvas canvas,
    required Path path,
    required Color color,
    required double strokeWidth,
    required StrokeStyle strokeStyle,
    required StrokeCap strokeCap,
    required StrokeJoin strokeJoin,
  }) {
    final paint = _strokePaint
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap
      ..strokeJoin = strokeJoin;

    switch (strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawPath(path, paint);
      case StrokeStyle.dashed:
        final dashed = buildDashedPath(
          path,
          strokeWidth * 2.0,
          strokeWidth * 2.0 * 1.2,
        );
        canvas.drawPath(dashed, paint);
      case StrokeStyle.dotted:
        final dotted = buildDashPatternPath(path, <double>[
          math.max(0.01, strokeWidth * 0.01),
          math.max(strokeWidth * 2.0, strokeWidth * 0.01),
        ]);
        canvas.drawPath(dotted, paint);
    }
  }

  double _resolveCornerRadius({
    required double cornerRadius,
    required double width,
    required double height,
  }) {
    if (cornerRadius <= 0) {
      return 0;
    }
    final maxRadius = (math.min(width, height)) / 2;
    return cornerRadius > maxRadius ? maxRadius : cornerRadius;
  }

  ({double lineWidth, double spacing}) _resolveHatch({
    required double strokeWidth,
  }) {
    final lineWidth = (1 + (strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    final spacing = (lineWidth * 4.0).clamp(3.0, 18.0);
    return (lineWidth: lineWidth, spacing: spacing);
  }

  double _resolveSerialStrokeWidth({required SerialNumberData data}) {
    const baseFontSize = ConfigDefaults.defaultSerialNumberFontSize;
    if (baseFontSize <= 0) {
      return math.max(data.strokeWidth, 0);
    }
    final scaled = data.strokeWidth * (data.fontSize / baseFontSize);
    if (!scaled.isFinite) {
      return 0;
    }
    return math.max(scaled, 0);
  }

  bool _isFreeDrawClosed({required FreeDrawData data, required DrawRect rect}) {
    final points = data.points;
    if (points.length < 3) {
      return false;
    }

    final first = points.first;
    final last = points.last;
    if (first == last) {
      return true;
    }

    const tolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= tolerance * tolerance;
  }

  Locale? _resolveLocale({
    required Locale? locale,
    required String? localeTag,
  }) {
    if (locale != null) {
      return locale;
    }
    if (localeTag == null || localeTag.isEmpty) {
      return null;
    }

    final parts = localeTag.replaceAll('_', '-').split('-');
    if (parts.isEmpty || parts.first.isEmpty) {
      return null;
    }
    if (parts.length == 1) {
      return Locale(parts.first);
    }
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }

    final scriptCandidate = parts[1];
    final hasScript = scriptCandidate.length == 4;
    if (hasScript) {
      return Locale.fromSubtags(
        languageCode: parts.first,
        scriptCode: scriptCandidate,
        countryCode: parts[2],
      );
    }
    return Locale.fromSubtags(languageCode: parts.first, countryCode: parts[1]);
  }

  Color _withOpacity(DrawColor color, double opacity) {
    final alpha = (color.alpha * opacity.clamp(0.0, 1.0)).round().clamp(0, 255);
    return Color((alpha << 24) | (color.toARGB32() & 0x00FFFFFF));
  }

  bool _isVisibleColor(Color color) => ((color.toARGB32() >>> 24) & 0xFF) > 0;
}

extension on Rect {
  DrawRect toDrawRect() =>
      DrawRect(minX: left, minY: top, maxX: right, maxY: bottom);
}

const flutterRenderTaskExecutor = FlutterRenderTaskExecutor();
