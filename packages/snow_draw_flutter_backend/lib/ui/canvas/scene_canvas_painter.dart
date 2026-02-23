import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import '../../extensions/draw_color_extensions.dart';
import '../../render/arrow/arrow_visual_cache.dart';
import '../../render/element_renderer.dart';
import '../../render/free_draw/free_draw_visual_cache.dart';
import '../../render/patterns/stroke_pattern_utils.dart';
import '../../render/tasks/flutter_render_task_executor.dart';
import '../../services/text/flutter_text_layout.dart';
import 'binding_highlight_style.dart';
import 'filter_pipeline/filter_segment_renderer.dart';
import 'free_draw_creation_preview_cache.dart';
import 'grid_shader_painter.dart';
import 'highlight_mask_painter.dart';
import 'render_keys.dart';
import 'serial_number_connection_painter.dart';
import 'watermark_painter.dart';

final ModuleLogger _sceneCanvasFallbackLog = LogService.fallback.render;

/// Scene canvas painter.
///
/// Renders the full document scene and interaction overlays.
///
/// The single-canvas architecture routes all draw content through this painter.
@immutable
class SceneCanvasPainter extends CustomPainter {
  const SceneCanvasPainter({required this.renderKey, required this.stateView});

  static const _directSolidPreviewPointThreshold = 32;
  static final _gapLabelPainter = TextPainter(textDirection: TextDirection.ltr);
  static final _freeDrawPreviewCache = FreeDrawCreationPreviewCache();
  static final _freeDrawStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static final _freeDrawDotPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final _freeDrawPointPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  static final _arrowOverlayPaints = _ArrowOverlayPaints();
  static final _arrowHoverStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  static Paint? _cachedBackgroundPaint;
  static Color? _cachedBackgroundColor;
  static final _minorGridPaint = Paint()..style = PaintingStyle.stroke;
  static final _majorGridPaint = Paint()..style = PaintingStyle.stroke;
  static var _minorGridPointBuffer = Float32List(0);
  static var _majorGridPointBuffer = Float32List(0);

  /// Render key for precise repaint decisions.
  final SceneCanvasRenderKey renderKey;

  /// Precomputed effective state view (needed for paint).
  final DrawStateView stateView;

  T? _firstPlannedTask<T extends RenderTask>() {
    for (final task in renderKey.framePlan.tasks) {
      if (task is T) {
        return task;
      }
    }
    return null;
  }

  List<T> _plannedTasks<T extends RenderTask>() {
    final tasks = <T>[];
    for (final task in renderKey.framePlan.tasks) {
      if (task is T) {
        tasks.add(task);
      }
    }
    return tasks;
  }

  GridConfig _gridConfigFromTask(GridRenderTask task) => GridConfig(
    enabled: task.enabled,
    size: task.size,
    lineColor: task.lineColor,
    lineOpacity: task.lineOpacity,
    majorLineOpacity: task.majorLineOpacity,
    lineWidth: task.lineWidth,
    majorLineEvery: task.majorLineEvery,
    minScreenSpacing: task.minScreenSpacing,
    minRenderSpacing: task.minRenderSpacing,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    if (!_isFreeDrawCreationInteraction(state.application.interaction)) {
      _freeDrawPreviewCache.clear();
    }
    final framePlan = renderKey.framePlan;
    final camera = framePlan.camera;
    final scale = framePlan.scaleFactor == 0 ? 1.0 : framePlan.scaleFactor;
    final plannedBackgroundTask = _firstPlannedTask<BackgroundRenderTask>();
    final plannedGridTask = _firstPlannedTask<GridRenderTask>();
    final effectiveBackgroundColor =
        plannedBackgroundTask?.color ?? ConfigDefaults.backgroundColor;
    final effectiveGridConfig = plannedGridTask == null
        ? const GridConfig()
        : _gridConfigFromTask(plannedGridTask);
    _drawBackground(canvas, size, effectiveBackgroundColor);
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );
    final shouldPaintGrid = _shouldPaintGrid(scale, effectiveGridConfig);
    final shaderUsed =
        shouldPaintGrid &&
        _drawGridWithShader(canvas, size, scale, effectiveGridConfig);

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    if (shouldPaintGrid && !shaderUsed) {
      _drawGridFallback(canvas, viewportRect, scale, effectiveGridConfig);
    }

    final creatingElement = renderKey.creatingElement;

    // Draw elements at or above the selected element to preserve z-order.
    _drawSceneElements(
      canvas: canvas,
      scale: scale,
      viewportRect: viewportRect,
      creatingElement: creatingElement,
    );

    // Draw creating element preview above the current scene content.
    if (creatingElement != null &&
        creatingElement.element.data is! FilterData) {
      final renderedWithLowLatencyPath = _renderFreeDrawCreatingPreview(
        canvas: canvas,
        interaction: state.application.interaction,
        viewportRect: viewportRect,
      );
      if (!renderedWithLowLatencyPath) {
        final previewElement = creatingElement.element.copyWith(
          rect: creatingElement.currentRect,
        );
        elementRenderer.renderElement(
          canvas: canvas,
          element: previewElement,
          scaleFactor: scale,
          elementRegistry: renderKey.elementRegistry,
          textMetricsService: renderKey.textMetricsService,
          locale: renderKey.locale,
        );
      }
    }

    final plannedHighlightMaskTask =
        _firstPlannedTask<HighlightMaskRenderTask>();
    if (plannedHighlightMaskTask != null) {
      _paintHighlightMask(
        canvas: canvas,
        task: plannedHighlightMaskTask,
        viewportRect: viewportRect,
        scale: scale,
        cameraPosition: Offset(camera.position.x, camera.position.y),
      );
    }

    final plannedWatermarkTask = _firstPlannedTask<WatermarkRenderTask>();
    if (plannedWatermarkTask != null) {
      canvas
        ..save()
        ..scale(1 / scale, 1 / scale)
        ..translate(-camera.position.x, -camera.position.y);
      paintWatermark(
        canvas: canvas,
        viewportSize: size,
        config: plannedWatermarkTask.config,
      );
      canvas.restore();
    }

    final plannedSnapGuidesTask = _firstPlannedTask<SnapGuidesRenderTask>();
    if (plannedSnapGuidesTask != null) {
      _drawSnapGuides(
        canvas: canvas,
        guides: plannedSnapGuidesTask.guides,
        config: plannedSnapGuidesTask.snapConfig,
        scale: scale,
      );
    }

    final plannedHoverTasks = _plannedTasks<HoverOutlineRenderTask>();
    for (final task in plannedHoverTasks) {
      _drawHoverOutlineFromTask(canvas: canvas, task: task, scale: scale);
    }

    final plannedSelectionOutlineTasks =
        _plannedTasks<SelectionOutlineRenderTask>();
    final plannedSelectionControlsTask =
        _firstPlannedTask<SelectionControlsRenderTask>();
    for (final task in plannedSelectionOutlineTasks) {
      _drawSelectionOutlineFromTask(canvas: canvas, task: task, scale: scale);
    }
    final controlsTask = plannedSelectionControlsTask;
    if (controlsTask != null) {
      _drawSelectionControlsFromTask(
        canvas: canvas,
        task: controlsTask,
        scale: scale,
      );
    }

    final plannedArrowBindingHighlightTask =
        _firstPlannedTask<ArrowBindingHighlightRenderTask>();
    if (plannedArrowBindingHighlightTask != null) {
      _drawArrowBindingHighlight(
        canvas: canvas,
        scale: scale,
        task: plannedArrowBindingHighlightTask,
      );
    }

    final plannedArrowOverlayTask =
        _firstPlannedTask<ArrowPointOverlayRenderTask>();
    if (plannedArrowOverlayTask != null) {
      _drawArrowPointOverlayTask(
        canvas: canvas,
        task: plannedArrowOverlayTask,
        scale: scale,
      );
    }

    final plannedBoxSelectionTask = _firstPlannedTask<BoxSelectionRenderTask>();
    if (plannedBoxSelectionTask != null) {
      _drawBoxSelectionPreviewElements(
        canvas: canvas,
        elements: plannedBoxSelectionTask.previewElements,
        selectionConfig: plannedBoxSelectionTask.selectionConfig,
        scale: scale,
      );
      _drawBoxSelection(
        canvas,
        plannedBoxSelectionTask.bounds,
        scale,
        plannedBoxSelectionTask.config,
      );
    }

    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size, DrawColor backgroundColor) {
    final color = backgroundColor.toFlutterColor();
    final paint = _resolveBackgroundPaint(color);
    canvas.drawRect(Offset.zero & size, paint);
  }

  static Paint _resolveBackgroundPaint(Color color) {
    if (_cachedBackgroundPaint != null && _cachedBackgroundColor == color) {
      return _cachedBackgroundPaint!;
    }
    _cachedBackgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    _cachedBackgroundColor = color;
    return _cachedBackgroundPaint!;
  }

  bool _shouldPaintGrid(double scale, GridConfig config) {
    final baseSize = config.size;
    if (!config.enabled || baseSize <= 0 || scale <= 0) {
      return false;
    }
    return baseSize * scale >= config.minRenderSpacing;
  }

  bool _drawGridWithShader(
    Canvas canvas,
    Size size,
    double scale,
    GridConfig config,
  ) {
    final shaderManager = GridShaderManager.instance;
    if (!shaderManager.isReady) {
      return false;
    }

    final minorOpacityRatio = _resolveMinorOpacityRatio(
      baseSize: config.size,
      scale: scale,
      minScreenSpacing: config.minScreenSpacing,
    );
    final majorEveryFactor = _resolveMajorEveryFactor(
      baseSize: config.size,
      majorEvery: config.majorLineEvery,
      scale: scale,
      minSpacing: config.minScreenSpacing,
    );

    return shaderManager.paintGrid(
      canvas: canvas,
      size: size,
      cameraPosition: Offset(
        renderKey.framePlan.camera.position.x,
        renderKey.framePlan.camera.position.y,
      ),
      scale: scale,
      config: config,
      minorOpacityRatio: minorOpacityRatio,
      majorEveryFactor: majorEveryFactor,
    );
  }

  void _drawGridFallback(
    Canvas canvas,
    DrawRect viewportRect,
    double scale,
    GridConfig config,
  ) {
    final baseSize = config.size;
    final minorStrokeWidth = config.lineWidth / scale;
    final majorStrokeWidth = minorStrokeWidth * 1.5;
    final screenSpacing = baseSize * scale;
    final showMinorLines = screenSpacing >= config.minScreenSpacing;
    final minorOpacityRatio = _resolveMinorOpacityRatio(
      baseSize: baseSize,
      scale: scale,
      minScreenSpacing: config.minScreenSpacing,
    );
    final majorEveryFactor = _resolveMajorEveryFactor(
      baseSize: baseSize,
      majorEvery: config.majorLineEvery,
      scale: scale,
      minSpacing: config.minScreenSpacing,
    );
    final majorStep = baseSize * majorEveryFactor;

    final minorColor = config.lineColor
        .withValues(alpha: config.lineOpacity * minorOpacityRatio * 0.5)
        .toFlutterColor();
    final majorColor = config.lineColor
        .withValues(alpha: config.majorLineOpacity)
        .toFlutterColor();
    final minorPaint = _minorGridPaint
      ..strokeWidth = minorStrokeWidth
      ..color = minorColor;
    final majorPaint = _majorGridPaint
      ..strokeWidth = majorStrokeWidth
      ..color = majorColor;

    if (showMinorLines) {
      final step = baseSize;
      final startXIndex = (viewportRect.minX / step).floor();
      final endXIndex = (viewportRect.maxX / step).ceil();
      final startYIndex = (viewportRect.minY / step).floor();
      final endYIndex = (viewportRect.maxY / step).ceil();

      final verticalLineCount = endXIndex - startXIndex + 1;
      final horizontalLineCount = endYIndex - startYIndex + 1;

      var majorVerticalCount = 0;
      var majorHorizontalCount = 0;
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        if (_isMajorLine(ix, majorEveryFactor)) {
          majorVerticalCount++;
        }
      }
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        if (_isMajorLine(iy, majorEveryFactor)) {
          majorHorizontalCount++;
        }
      }
      final minorVerticalCount = verticalLineCount - majorVerticalCount;
      final minorHorizontalCount = horizontalLineCount - majorHorizontalCount;

      final majorPointCount = (majorVerticalCount + majorHorizontalCount) * 4;
      final minorPointCount = (minorVerticalCount + minorHorizontalCount) * 4;
      _majorGridPointBuffer = _ensurePointBuffer(
        _majorGridPointBuffer,
        majorPointCount,
      );
      _minorGridPointBuffer = _ensurePointBuffer(
        _minorGridPointBuffer,
        minorPointCount,
      );
      final majorPoints = _majorGridPointBuffer;
      final minorPoints = _minorGridPointBuffer;

      var majorIdx = 0;
      var minorIdx = 0;

      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * step;
        if (_isMajorLine(ix, majorEveryFactor)) {
          majorPoints[majorIdx++] = x;
          majorPoints[majorIdx++] = viewportRect.minY;
          majorPoints[majorIdx++] = x;
          majorPoints[majorIdx++] = viewportRect.maxY;
        } else {
          minorPoints[minorIdx++] = x;
          minorPoints[minorIdx++] = viewportRect.minY;
          minorPoints[minorIdx++] = x;
          minorPoints[minorIdx++] = viewportRect.maxY;
        }
      }

      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * step;
        if (_isMajorLine(iy, majorEveryFactor)) {
          majorPoints[majorIdx++] = viewportRect.minX;
          majorPoints[majorIdx++] = y;
          majorPoints[majorIdx++] = viewportRect.maxX;
          majorPoints[majorIdx++] = y;
        } else {
          minorPoints[minorIdx++] = viewportRect.minX;
          minorPoints[minorIdx++] = y;
          minorPoints[minorIdx++] = viewportRect.maxX;
          minorPoints[minorIdx++] = y;
        }
      }

      if (minorIdx > 0) {
        canvas.drawRawPoints(
          PointMode.lines,
          _slicePointBuffer(minorPoints, minorIdx),
          minorPaint,
        );
      }
      if (majorIdx > 0) {
        canvas.drawRawPoints(
          PointMode.lines,
          _slicePointBuffer(majorPoints, majorIdx),
          majorPaint,
        );
      }
      return;
    }

    final startXIndex = (viewportRect.minX / majorStep).floor();
    final endXIndex = (viewportRect.maxX / majorStep).ceil();
    final startYIndex = (viewportRect.minY / majorStep).floor();
    final endYIndex = (viewportRect.maxY / majorStep).ceil();

    final verticalCount = endXIndex - startXIndex + 1;
    final horizontalCount = endYIndex - startYIndex + 1;
    final majorPointCount = (verticalCount + horizontalCount) * 4;
    _majorGridPointBuffer = _ensurePointBuffer(
      _majorGridPointBuffer,
      majorPointCount,
    );
    final majorPoints = _majorGridPointBuffer;

    var idx = 0;

    for (var ix = startXIndex; ix <= endXIndex; ix++) {
      final x = ix * majorStep;
      majorPoints[idx++] = x;
      majorPoints[idx++] = viewportRect.minY;
      majorPoints[idx++] = x;
      majorPoints[idx++] = viewportRect.maxY;
    }

    for (var iy = startYIndex; iy <= endYIndex; iy++) {
      final y = iy * majorStep;
      majorPoints[idx++] = viewportRect.minX;
      majorPoints[idx++] = y;
      majorPoints[idx++] = viewportRect.maxX;
      majorPoints[idx++] = y;
    }

    if (idx > 0) {
      canvas.drawRawPoints(
        PointMode.lines,
        _slicePointBuffer(majorPoints, idx),
        majorPaint,
      );
    }
  }

  int _resolveMajorEveryFactor({
    required double baseSize,
    required int majorEvery,
    required double scale,
    required double minSpacing,
  }) {
    final normalizedMajorEvery = majorEvery < 1 ? 1 : majorEvery;
    if (normalizedMajorEvery == 1) {
      return 1;
    }
    if (baseSize <= 0 || scale <= 0 || minSpacing <= 0) {
      return normalizedMajorEvery;
    }

    var factor = normalizedMajorEvery;
    var step = baseSize * factor;
    while (step * scale < minSpacing) {
      factor *= normalizedMajorEvery;
      step = baseSize * factor;
    }
    return factor;
  }

  double _resolveMinorOpacityRatio({
    required double baseSize,
    required double scale,
    required double minScreenSpacing,
  }) {
    if (scale <= 0 || baseSize <= 0 || minScreenSpacing <= 0) {
      return 0;
    }
    final spacingAtScale = baseSize * scale;
    final startSpacing = baseSize;
    if (spacingAtScale >= startSpacing) {
      return 1;
    }
    if (startSpacing <= minScreenSpacing) {
      return 0;
    }
    final t =
        (spacingAtScale - minScreenSpacing) / (startSpacing - minScreenSpacing);
    return _smoothStep(t.clamp(0.0, 1.0));
  }

  double _smoothStep(double t) => t * t * (3 - 2 * t);

  Float32List _ensurePointBuffer(Float32List current, int requiredLength) {
    if (requiredLength <= current.length) {
      return current;
    }

    var nextLength = current.isEmpty ? 128 : current.length;
    while (nextLength < requiredLength) {
      nextLength *= 2;
    }
    return Float32List(nextLength);
  }

  Float32List _slicePointBuffer(Float32List buffer, int usedLength) {
    if (usedLength == buffer.length) {
      return buffer;
    }
    return Float32List.sublistView(buffer, 0, usedLength);
  }

  bool _isMajorLine(int index, int majorEvery) =>
      majorEvery > 0 && index % majorEvery == 0;

  bool _isFreeDrawCreationInteraction(InteractionState interaction) =>
      interaction is CreatingState && interaction.elementData is FreeDrawData;

  bool _renderFreeDrawCreatingPreview({
    required Canvas canvas,
    required InteractionState interaction,
    required DrawRect viewportRect,
  }) {
    if (interaction is! CreatingState) {
      return false;
    }

    final data = interaction.elementData;
    final mode = interaction.creationMode;
    if (data is! FreeDrawData || mode is! FreeDrawCreationMode) {
      return false;
    }

    final points = mode.worldPoints;
    if (points == null || points.isEmpty) {
      _freeDrawPreviewCache.clear();
      return false;
    }

    final strokeOpacity = (data.color.a * interaction.elementOpacity).clamp(
      0.0,
      1.0,
    );
    if (strokeOpacity <= 0 || data.strokeWidth <= 0) {
      _freeDrawPreviewCache.clear();
      return true;
    }

    final strokeColor = data.color
        .withValues(alpha: strokeOpacity)
        .toFlutterColor();
    final strokePaint = _freeDrawStrokePaint
      ..strokeWidth = data.strokeWidth
      ..color = strokeColor;

    if (data.strokeStyle == StrokeStyle.solid) {
      final cachedPointCount = _resolveSolidPreviewPointCount(
        mode: mode,
        points: points,
      );
      if (cachedPointCount > 1) {
        if (cachedPointCount <= _directSolidPreviewPointThreshold) {
          _freeDrawPreviewCache.clear();
          _drawSolidPreviewDirect(
            canvas: canvas,
            points: points,
            visiblePointCount: cachedPointCount,
            strokePaint: strokePaint,
          );
        } else {
          _freeDrawPreviewCache
            ..sync(
              elementId: interaction.elementId,
              points: points,
              visiblePointCount: cachedPointCount,
              signature: FreeDrawPreviewStrokeSignature(
                strokeStyle: data.strokeStyle,
                strokeWidth: data.strokeWidth,
                strokeColor: strokeColor,
              ),
              strokePaint: strokePaint,
            )
            ..paint(
              canvas: canvas,
              viewportRect: viewportRect,
              strokePaint: strokePaint,
            );
        }
      } else {
        _freeDrawPreviewCache.clear();
      }
    } else {
      _freeDrawPreviewCache.clear();
      final previewPath = _resolvePreviewPath(mode: mode, points: points);
      if (previewPath != null) {
        _drawFreeDrawStrokePath(
          canvas: canvas,
          path: previewPath,
          data: data,
          strokePaint: strokePaint,
          strokeColor: strokeColor,
        );
      }
    }

    if (mode.isLineActive &&
        mode.lineAnchor != null &&
        mode.lineCurrent != null) {
      final anchor = mode.lineAnchor!;
      final current = mode.lineCurrent!;
      if (data.strokeStyle == StrokeStyle.solid) {
        canvas.drawLine(
          Offset(anchor.x, anchor.y),
          Offset(current.x, current.y),
          strokePaint,
        );
      } else {
        final activeLinePath = Path()
          ..moveTo(anchor.x, anchor.y)
          ..lineTo(current.x, current.y);
        _drawFreeDrawStrokePath(
          canvas: canvas,
          path: activeLinePath,
          data: data,
          strokePaint: strokePaint,
          strokeColor: strokeColor,
        );
      }
    }

    final isSinglePointStroke =
        points.length == 1 ||
        (points.length == 2 &&
            points.first.x == points.last.x &&
            points.first.y == points.last.y);
    if (isSinglePointStroke && !mode.isLineActive) {
      final point = points.first;
      final pointPaint = _freeDrawPointPaint..color = strokeColor;
      canvas.drawCircle(
        Offset(point.x, point.y),
        data.strokeWidth / 2,
        pointPaint,
      );
    }

    return true;
  }

  int _resolveSolidPreviewPointCount({
    required FreeDrawCreationMode mode,
    required List<DrawPoint> points,
  }) {
    if (points.isEmpty) {
      return 0;
    }
    if (!mode.isLineActive) {
      return points.length;
    }
    if (points.length <= 2) {
      return 0;
    }
    return points.length - 1;
  }

  void _drawSolidPreviewDirect({
    required Canvas canvas,
    required List<DrawPoint> points,
    required int visiblePointCount,
    required Paint strokePaint,
  }) {
    if (visiblePointCount < 2) {
      return;
    }

    final first = points.first;
    final path = Path()..moveTo(first.x, first.y);
    var previous = first;
    var hasSegment = false;
    for (var index = 1; index < visiblePointCount; index++) {
      final point = points[index];
      if (point.x == previous.x && point.y == previous.y) {
        previous = point;
        continue;
      }
      path.lineTo(point.x, point.y);
      previous = point;
      hasSegment = true;
    }
    if (hasSegment) {
      canvas.drawPath(path, strokePaint);
    }
  }

  Path? _resolvePreviewPath({
    required FreeDrawCreationMode mode,
    required List<DrawPoint> points,
  }) {
    final previewPoints = mode.previewPoints ?? points;
    if (previewPoints.length < 2) {
      return null;
    }
    final path = Path()..moveTo(previewPoints.first.x, previewPoints.first.y);
    for (var index = 1; index < previewPoints.length; index++) {
      final point = previewPoints[index];
      path.lineTo(point.x, point.y);
    }
    return path;
  }

  void _drawFreeDrawStrokePath({
    required Canvas canvas,
    required Path path,
    required FreeDrawData data,
    required Paint strokePaint,
    required Color strokeColor,
  }) {
    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawPath(path, strokePaint);
      case StrokeStyle.dashed:
        final dashLength = data.strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        final dashedPath = buildDashedPath(path, dashLength, gapLength);
        canvas.drawPath(dashedPath, strokePaint);
      case StrokeStyle.dotted:
        final dotSpacing = data.strokeWidth * 2.0;
        final dotRadius = data.strokeWidth * 0.5;
        final dotPositions = buildDotPositions(path, dotSpacing);
        if (dotPositions.isEmpty) {
          return;
        }
        final dotPaint = _freeDrawDotPaint
          ..strokeWidth = dotRadius * 2
          ..color = strokeColor;
        canvas.drawRawPoints(PointMode.points, dotPositions, dotPaint);
    }
  }

  void _paintHighlightMask({
    required Canvas canvas,
    required HighlightMaskRenderTask task,
    required DrawRect viewportRect,
    required double scale,
    required Offset cameraPosition,
  }) {
    if (task.highlights.isEmpty) {
      return;
    }

    paintHighlightMask(
      canvas: canvas,
      highlights: task.highlights,
      viewportRect: viewportRect,
      maskConfig: task.config,
      scaleFactor: scale,
      cameraPosition: cameraPosition,
    );
  }

  void _drawSceneElements({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required CreatingElementSnapshot? creatingElement,
  }) {
    final document = stateView.state.domain.document;
    final excludedElementId =
        creatingElement != null &&
            document.getElementById(creatingElement.element.id) != null
        ? creatingElement.element.id
        : null;
    var effectiveElements = resolveVisibleElementScene(
      document: document,
      viewportRect: viewportRect,
      previewElementsById: renderKey.previewElementsById,
      excludedElementId: excludedElementId,
    );

    if (creatingElement != null && creatingElement.element.data is FilterData) {
      final previewFilter = creatingElement.element.copyWith(
        rect: creatingElement.currentRect,
      );
      effectiveElements = List<ElementState>.of(effectiveElements)
        ..add(previewFilter);
    }

    _paintElementScene(
      canvas: canvas,
      scale: scale,
      viewportRect: viewportRect,
      effectiveElements: effectiveElements,
    );
  }

  void _paintElementScene({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required List<ElementState> effectiveElements,
  }) {
    if (effectiveElements.isEmpty) {
      return;
    }

    final sceneContext = _resolveSceneRenderContext(
      elements: effectiveElements,
    );

    void paintElement(Canvas sceneCanvas, ElementState element) =>
        _paintSceneElement(
          canvas: sceneCanvas,
          element: element,
          scale: scale,
          sceneContext: sceneContext,
        );

    if (!sceneContext.hasFilterElement) {
      _paintElementsDirectly(
        canvas: canvas,
        elements: effectiveElements,
        paintElement: paintElement,
      );
      return;
    }

    final filterCacheContext = sceneContext.shouldPaintSerialConnectors
        ? null
        : _buildFilterCacheContext(scale: scale);
    filterSegmentRenderer.paint(
      canvas: canvas,
      elements: effectiveElements,
      paintElement: paintElement,
      cacheContext: filterCacheContext,
      visibleBounds: Rect.fromLTWH(
        viewportRect.minX,
        viewportRect.minY,
        viewportRect.width,
        viewportRect.height,
      ),
      volatileElementIds: sceneContext.volatileElementIds,
    );
    if (renderKey.performanceMonitoringEnabled) {
      final diagnostics = filterSegmentRenderer.lastDiagnostics;
      if (diagnostics.pictureRecorders > 12 || diagnostics.filterPasses > 6) {
        _sceneCanvasFallbackLog.warning('Heavy interactive filter frame', {
          'pictureRecorders': diagnostics.pictureRecorders,
          'saveLayers': diagnostics.saveLayers,
          'filterPasses': diagnostics.filterPasses,
          'batchCount': diagnostics.batchCount,
          'batchCacheHits': diagnostics.batchCacheHits,
          'batchCacheMisses': diagnostics.batchCacheMisses,
        });
      }
    }
  }

  _SceneRenderContext _resolveSceneRenderContext({
    required List<ElementState> elements,
  }) {
    final document = stateView.state.domain.document;
    final previewElements = renderKey.previewElementsById;
    final volatilePreviewIds = _resolveVolatilePreviewElementIds(
      previewElements,
    );
    final creatingFilterId = _resolveCreatingFilterId();
    final sceneAnalysis = _resolveSceneRenderAnalysis(
      document: document,
      elements: elements,
      previewElementsById: previewElements,
    );

    final serialConnectorSnapshot = sceneAnalysis.shouldPaintSerialConnectors
        ? resolveSerialNumberConnectorSnapshot(
            stateView,
            previewElementsById: previewElements,
            visibleTextElementIds: sceneAnalysis.visibleTextIds,
          )
        : const SerialNumberConnectorSnapshot(
            connectorsByTextId: <String, List<SerialNumberTextConnector>>{},
            volatileTextElementIds: <String>{},
          );
    final interactionVolatileElementIds = _resolveVolatileElementIds(
      volatilePreviewIds: volatilePreviewIds,
      creatingFilterId: creatingFilterId,
      serialConnectorTextIds: serialConnectorSnapshot.volatileTextElementIds,
    );

    return _SceneRenderContext(
      hasFilterElement: sceneAnalysis.hasFilterElement,
      shouldPaintSerialConnectors: sceneAnalysis.shouldPaintSerialConnectors,
      serialConnectors: serialConnectorSnapshot.connectorsByTextId,
      volatileElementIds: interactionVolatileElementIds,
      plannedElementTasksById: renderKey.plannedElementTasksById,
    );
  }

  _SceneRenderAnalysis _resolveSceneRenderAnalysis({
    required DocumentState document,
    required List<ElementState> elements,
    required Map<String, ElementState> previewElementsById,
  }) {
    final canHaveSerialConnectors =
        document.boundTextIds.isNotEmpty ||
        _hasSerialPreviewElements(previewElementsById);
    var hasFilterElement = false;
    final visibleTextIds = <String>{};
    for (final element in elements) {
      if (!hasFilterElement && element.data is FilterData) {
        hasFilterElement = true;
      }
      if (canHaveSerialConnectors &&
          element.opacity > 0 &&
          element.data is TextData) {
        visibleTextIds.add(element.id);
      }
    }
    if (canHaveSerialConnectors) {
      _includeEditingTextIdForSerialConnectors(
        document: document,
        previewElementsById: previewElementsById,
        visibleTextIds: visibleTextIds,
      );
    }

    final shouldPaintSerialConnectors =
        visibleTextIds.isNotEmpty &&
        _shouldPaintSerialConnectors(
          boundTextIds: document.boundTextIds,
          previewElementsById: previewElementsById,
          visibleTextIds: visibleTextIds,
        );

    final analysis = _SceneRenderAnalysis(
      hasFilterElement: hasFilterElement,
      visibleTextIds: visibleTextIds,
      shouldPaintSerialConnectors: shouldPaintSerialConnectors,
    );
    return analysis;
  }

  bool _hasSerialPreviewElements(
    Map<String, ElementState> previewElementsById,
  ) {
    for (final preview in previewElementsById.values) {
      if (preview.data is SerialNumberData) {
        return true;
      }
    }
    return false;
  }

  void _paintSceneElement({
    required Canvas canvas,
    required ElementState element,
    required double scale,
    required _SceneRenderContext sceneContext,
  }) {
    final plannedTasks = sceneContext.plannedElementTasksById[element.id];
    if (plannedTasks != null && plannedTasks.isNotEmpty) {
      flutterRenderTaskExecutor.executeTasks(
        canvas: canvas,
        tasks: plannedTasks,
        elementRegistry: renderKey.elementRegistry,
        textMetricsService: renderKey.textMetricsService,
        locale: renderKey.locale,
      );
    } else {
      elementRenderer.renderElement(
        canvas: canvas,
        element: element,
        scaleFactor: scale,
        elementRegistry: renderKey.elementRegistry,
        textMetricsService: renderKey.textMetricsService,
        locale: renderKey.locale,
      );
    }
    if (sceneContext.shouldPaintSerialConnectors) {
      drawSerialNumberConnectorsForText(
        canvas: canvas,
        textElementId: element.id,
        connectorsByTextId: sceneContext.serialConnectors,
      );
    }
  }

  FilterRenderCacheContext _buildFilterCacheContext({required double scale}) {
    final localeTag = renderKey.locale?.toLanguageTag() ?? '';
    return FilterRenderCacheContext(
      textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
      scaleKey: (scale * 1000).round(),
      localeTag: localeTag,
    );
  }

  void _paintElementsDirectly({
    required Canvas canvas,
    required List<ElementState> elements,
    required void Function(Canvas sceneCanvas, ElementState element)
    paintElement,
  }) {
    for (final element in elements) {
      paintElement(canvas, element);
    }
  }

  Set<String> _resolveVolatileElementIds({
    required Set<String> volatilePreviewIds,
    String? creatingFilterId,
    Iterable<String> serialConnectorTextIds = const <String>{},
  }) {
    if (volatilePreviewIds.isEmpty &&
        creatingFilterId == null &&
        serialConnectorTextIds.isEmpty) {
      return const <String>{};
    }

    final volatileElementIds = <String>{}..addAll(volatilePreviewIds);
    if (creatingFilterId != null) {
      volatileElementIds.add(creatingFilterId);
    }
    volatileElementIds.addAll(serialConnectorTextIds);
    return volatileElementIds;
  }

  Set<String> _resolveVolatilePreviewElementIds(
    Map<String, ElementState> previewElementsById,
  ) {
    if (previewElementsById.isEmpty) {
      return const <String>{};
    }

    final document = stateView.state.domain.document;
    final volatileIds = <String>{};
    for (final entry in previewElementsById.entries) {
      final persisted = document.getElementById(entry.key);
      if (persisted == null || !identical(persisted, entry.value)) {
        volatileIds.add(entry.key);
      }
    }
    return volatileIds;
  }

  String? _resolveCreatingFilterId() {
    final creatingElement = renderKey.creatingElement?.element;
    if (creatingElement == null || creatingElement.data is! FilterData) {
      return null;
    }
    return creatingElement.id;
  }

  void _includeEditingTextIdForSerialConnectors({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
    required Set<String> visibleTextIds,
  }) {
    final interaction = stateView.state.application.interaction;
    if (interaction is! TextEditingState || interaction.isNew) {
      return;
    }

    final editingTextId = interaction.elementId;
    final previewElement = previewElementsById[editingTextId];
    if (previewElement != null) {
      if (previewElement.data is TextData) {
        visibleTextIds.add(editingTextId);
      }
      return;
    }

    final persistedElement = document.getElementById(editingTextId);
    if (persistedElement?.data is TextData) {
      visibleTextIds.add(editingTextId);
    }
  }

  void _drawArrowBindingHighlight({
    required Canvas canvas,
    required double scale,
    required ArrowBindingHighlightRenderTask task,
  }) {
    if (task.elementIds.isEmpty) {
      return;
    }
    final strokeColor = task.strokeColor.toFlutterColor();
    final paint = createBindingHighlightPaint(color: strokeColor, scale: scale);

    for (final elementId in task.elementIds) {
      final element = stateView.state.domain.document.getElementById(elementId);
      if (element == null) {
        continue;
      }
      final effectiveElement = stateView.effectiveElement(element);
      final rect = effectiveElement.rect;
      final data = effectiveElement.data;
      final highlightRect = Rect.fromLTWH(
        rect.minX,
        rect.minY,
        rect.width,
        rect.height,
      );
      final outerRect = resolveBindingHighlightOuterRect(
        highlightRect,
        paint.strokeWidth,
      );

      canvas.save();
      if (effectiveElement.rotation != 0) {
        canvas
          ..translate(rect.centerX, rect.centerY)
          ..rotate(effectiveElement.rotation)
          ..translate(-rect.centerX, -rect.centerY);
      }
      if (data is RectangleData) {
        if (data.cornerRadius > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              outerRect,
              Radius.circular(
                resolveBindingHighlightOuterRadius(
                  data.cornerRadius,
                  paint.strokeWidth,
                ),
              ),
            ),
            paint,
          );
        } else {
          canvas.drawRect(outerRect, paint);
        }
      } else if (data is TextData) {
        canvas.drawRect(outerRect, paint);
      } else if (data is SerialNumberData) {
        final radius = resolveBindingHighlightOuterRadius(
          math.min(rect.width, rect.height) / 2,
          paint.strokeWidth,
        );
        if (radius > 0) {
          final circleRect = Rect.fromCircle(
            center: Offset(rect.centerX, rect.centerY),
            radius: radius,
          );
          canvas.drawOval(circleRect, paint);
        }
      }
      canvas.restore();
    }
  }

  void _drawHoverOutlineFromTask({
    required Canvas canvas,
    required HoverOutlineRenderTask task,
    required double scale,
  }) {
    final element = task.element;
    final config = task.config;
    if (element.data is ArrowLikeData) {
      _drawArrowHoverOutline(
        canvas: canvas,
        element: element,
        config: config,
        scale: scale,
      );
      return;
    }

    if (task.useTextUnderlineStyle && element.data is TextData) {
      _drawTextHoverUnderlines(
        canvas: canvas,
        element: element,
        config: config,
        scale: scale,
      );
      return;
    }

    if (element.data is FreeDrawData) {
      _drawFreeDrawHoverOutline(
        canvas: canvas,
        element: element,
        config: config,
        scale: scale,
      );
      return;
    }

    elementRenderer.renderSelectionOutline(
      canvas: canvas,
      bounds: element.rect,
      scaleFactor: scale,
      config: config,
      rotation: element.rotation,
      rotationCenter: element.center,
      dashed: element.data is! RectangleData,
    );
  }

  void _drawSelectionOutlineFromTask({
    required Canvas canvas,
    required SelectionOutlineRenderTask task,
    required double scale,
  }) {
    elementRenderer.renderSelectionOutline(
      canvas: canvas,
      bounds: task.bounds,
      scaleFactor: scale,
      config: task.config,
      rotation: task.rotation,
      rotationCenter: task.rotationCenter,
      dashed: task.dashed,
    );
  }

  void _drawSelectionControlsFromTask({
    required Canvas canvas,
    required SelectionControlsRenderTask task,
    required double scale,
  }) {
    elementRenderer.renderSelection(
      canvas: canvas,
      bounds: task.bounds,
      scaleFactor: scale,
      config: task.config,
      rotation: task.rotation,
      rotationCenter: task.rotationCenter,
      dashed: task.dashed,
      cornerHandleOffset: task.cornerHandleOffset,
    );
    if (!task.showRotationHandle) {
      return;
    }
    elementRenderer.renderRotationHandle(
      canvas: canvas,
      bounds: task.bounds,
      scaleFactor: scale,
      config: task.config,
      rotation: task.rotation,
      rotationCenter: task.rotationCenter,
    );
  }

  void _drawArrowPointOverlayTask({
    required Canvas canvas,
    required ArrowPointOverlayRenderTask task,
    required double scale,
  }) {
    if (task.handles.isEmpty) {
      return;
    }

    final elementId = task.handles.first.elementId;
    final previewElement = renderKey.previewElementsById[elementId];
    ElementState? effectiveElement;
    if (previewElement != null) {
      effectiveElement = previewElement;
    } else {
      final documentElement = stateView.state.domain.document.getElementById(
        elementId,
      );
      if (documentElement == null) {
        return;
      }
      effectiveElement = stateView.effectiveElement(documentElement);
    }
    if (effectiveElement.data is! ArrowLikeData) {
      return;
    }

    final handles = <ArrowPointHandle>[
      for (final handle in task.handles)
        if (handle.elementId == elementId) handle,
    ];
    if (handles.isEmpty) {
      return;
    }

    _drawArrowPointHandles(
      canvas: canvas,
      element: effectiveElement,
      handles: handles,
      selectionConfig: task.selectionConfig,
      activeHandle: task.activeHandle,
      hoveredHandle: task.hoveredHandle,
      deleteIndicatorVisible: task.deleteIndicatorVisible,
      scale: scale,
    );
  }

  void _drawArrowPointHandles({
    required Canvas canvas,
    required ElementState element,
    required List<ArrowPointHandle> handles,
    required SelectionConfig selectionConfig,
    required ArrowPointHandle? activeHandle,
    required ArrowPointHandle? hoveredHandle,
    required bool deleteIndicatorVisible,
    required double scale,
  }) {
    final addablePoints = <ArrowPointHandle>[];
    final turningPoints = <ArrowPointHandle>[];
    final loopPoints = <ArrowPointHandle>[];
    for (final handle in handles) {
      switch (handle.kind) {
        case ArrowPointKind.turning:
          turningPoints.add(handle);
        case ArrowPointKind.addable:
          addablePoints.add(handle);
        case ArrowPointKind.loopStart:
        case ArrowPointKind.loopEnd:
          loopPoints.add(handle);
      }
    }
    if (turningPoints.isEmpty && addablePoints.isEmpty && loopPoints.isEmpty) {
      return;
    }

    final baseHandleSize = selectionConfig.render.controlPointSize / scale;
    final handleSize = baseHandleSize * ConfigDefaults.arrowPointSizeMultiplier;
    final strokeWidth = selectionConfig.render.strokeWidth / scale;
    final fillColor = selectionConfig.render.cornerFillColor.toFlutterColor();
    final strokeColor = selectionConfig.render.strokeColor.toFlutterColor();
    final highlightStroke = strokeColor.withValues(alpha: 0.95);

    final shouldDelete =
        deleteIndicatorVisible &&
        activeHandle != null &&
        activeHandle.elementId == element.id;
    final deleteHandle = shouldDelete ? activeHandle : null;
    final deletePosition = deleteHandle == null
        ? null
        : _resolveHandlePositionFromHandles(handles, deleteHandle);

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(element.rect.centerX, element.rect.centerY)
        ..rotate(element.rotation)
        ..translate(-element.rect.centerX, -element.rect.centerY);
    }
    canvas.translate(element.rect.minX, element.rect.minY);

    final addableRadius = handleSize * 0.5;
    final turnRadius = handleSize * 0.5;
    final loopOuterRadius = handleSize * 1.0;
    final loopInnerRadius = handleSize * 0.5;
    final hoverOuterRadius = loopOuterRadius;
    final paints = _arrowOverlayPaints
      ..configure(
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        strokeColor: strokeColor,
        highlightStrokeColor: highlightStroke,
      );

    for (final handle in addablePoints) {
      final center = _localOffset(element.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      final isFixed = handle.isFixed;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, paints.hoverOuterFill);
      }
      final fillPaint = isFixed
          ? paints.fixedFill
          : (isHighlighted
                ? paints.addableFillHighlighted
                : paints.addableFill);
      final strokePaint = isFixed
          ? (isHighlighted ? paints.fixedStrokeHighlighted : paints.fixedStroke)
          : (isHighlighted
                ? paints.addableStrokeHighlighted
                : paints.addableStroke);
      canvas
        ..drawCircle(center, addableRadius, fillPaint)
        ..drawCircle(center, addableRadius, strokePaint);
    }

    for (final handle in turningPoints) {
      final center = _localOffset(element.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, paints.hoverOuterFill);
      }
      final strokePaint = isHighlighted
          ? paints.turningStrokeHighlighted
          : paints.turningStroke;
      canvas
        ..drawCircle(center, turnRadius, paints.turningFill)
        ..drawCircle(center, turnRadius, strokePaint);
    }

    for (final handle in loopPoints) {
      final center = _localOffset(element.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, paints.hoverOuterFill);
      }
      final radius = handle.kind == ArrowPointKind.loopEnd
          ? loopOuterRadius
          : loopInnerRadius;
      if (handle.kind == ArrowPointKind.loopStart) {
        canvas.drawCircle(center, radius, paints.turningFill);
      }
      canvas.drawCircle(
        center,
        radius,
        isHighlighted ? paints.loopStrokeHighlighted : paints.loopStroke,
      );
    }

    if (deletePosition != null) {
      final center = _localOffset(element.rect, deletePosition);
      canvas.drawCircle(center, turnRadius * 1.35, paints.deleteStroke);
    }

    canvas.restore();
  }

  void _drawArrowHoverOutline({
    required Canvas canvas,
    required ElementState element,
    required SelectionConfig config,
    required double scale,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      return;
    }
    if (_drawLineHoverOutlineFastPath(
      canvas: canvas,
      element: element,
      data: data,
      config: config,
      scale: scale,
    )) {
      return;
    }

    final rect = element.rect;
    final cached = arrowVisualCache.resolve(element: element, data: data);
    if (cached.geometry.localPoints.length < 2) {
      return;
    }

    // Use selection stroke width for the hover outline.
    final hoverStrokeWidth = config.render.strokeWidth;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    // Use hover selection color with modified appearance
    final hoverColor = config.render.strokeColor.toFlutterColor();
    final strokePaint = _arrowHoverStrokePaint
      ..strokeWidth = hoverStrokeWidth / scale
      ..color = hoverColor;

    // Draw shaft (always solid for hover outline)
    canvas.drawPath(cached.shaftPath, strokePaint);

    for (final arrowheadPath in cached.arrowheadPaths) {
      canvas.drawPath(arrowheadPath, strokePaint);
    }

    canvas.restore();
  }

  bool _drawLineHoverOutlineFastPath({
    required Canvas canvas,
    required ElementState element,
    required ArrowLikeData data,
    required SelectionConfig config,
    required double scale,
  }) {
    if (data is! LineData || data.points.length != 2) {
      return false;
    }

    final rect = element.rect;
    if (!rect.width.isFinite || !rect.height.isFinite) {
      return false;
    }
    final startPoint = data.points.first;
    final endPoint = data.points.last;
    final start = Offset(startPoint.x * rect.width, startPoint.y * rect.height);
    final end = Offset(endPoint.x * rect.width, endPoint.y * rect.height);
    if (!start.dx.isFinite ||
        !start.dy.isFinite ||
        !end.dx.isFinite ||
        !end.dy.isFinite) {
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

    final hoverStrokeWidth = config.render.strokeWidth;
    final hoverColor = config.render.strokeColor.toFlutterColor();
    final strokePaint = _arrowHoverStrokePaint
      ..strokeWidth = hoverStrokeWidth / scale
      ..color = hoverColor;
    canvas
      ..drawLine(start, end, strokePaint)
      ..restore();
    return true;
  }

  void _drawTextHoverUnderlines({
    required Canvas canvas,
    required ElementState element,
    required SelectionConfig config,
    required double scale,
  }) {
    final data = element.data;
    if (data is! TextData) {
      return;
    }

    final rect = element.rect;
    final rotation = element.rotation;

    // Get text layout to access line information
    final layout = layoutText(
      data: data,
      maxWidth: rect.width,
      minWidth: rect.width,
      locale: renderKey.locale,
    );

    // Get text boxes for each line
    final text = data.text.isEmpty ? ' ' : data.text;
    final textBoxes = layout.paragraph.getBoxesForRange(
      0,
      text.length,
      boxHeightStyle: BoxHeightStyle.strut,
    );

    if (textBoxes.isEmpty) {
      return;
    }

    // Calculate text offset based on vertical alignment
    final textOffset = _resolveTextOffsetForUnderline(
      containerSize: Size(rect.width, rect.height),
      textSize: layout.size,
      verticalAlign: data.verticalAlign,
    );

    canvas.save();
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    // Use hover selection color for underlines
    final underlineColor = config.render.strokeColor.toFlutterColor();
    final underlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale
      ..color = underlineColor
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Draw underline for each line
    for (final box in textBoxes) {
      // Filter out boxes with width less than 0.5 (blank lines)
      if (box.right - box.left < 0.5) {
        continue;
      }
      final y = box.bottom + textOffset.dy;
      final startX = box.left + textOffset.dx;
      final endX = box.right + textOffset.dx;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), underlinePaint);
    }

    canvas.restore();
  }

  void _drawFreeDrawHoverOutline({
    required Canvas canvas,
    required ElementState element,
    required SelectionConfig config,
    required double scale,
  }) {
    _drawFreeDrawOutline(
      canvas: canvas,
      element: element,
      scale: scale,
      color: config.render.strokeColor.toFlutterColor(),
    );
  }

  /// Draws a 1px free-draw outline that follows the actual
  /// rendered stroke shape.
  ///
  /// Reuses the cached smooth center-line path from
  /// [FreeDrawVisualCache] to avoid an expensive O(n) rebuild
  /// on every hover frame.
  void _drawFreeDrawOutline({
    required Canvas canvas,
    required ElementState element,
    required double scale,
    required Color color,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      return;
    }

    final cached = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );
    if (cached.pointCount < 2) {
      return;
    }

    final rect = element.rect;
    final path = cached.path;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas
      ..translate(rect.minX, rect.minY)
      ..drawPath(path, strokePaint)
      ..restore();
  }

  Offset _resolveTextOffsetForUnderline({
    required Size containerSize,
    required Size textSize,
    required TextVerticalAlign verticalAlign,
  }) {
    var dy = 0.0;

    switch (verticalAlign) {
      case TextVerticalAlign.top:
        dy = 0;
      case TextVerticalAlign.center:
        dy = (containerSize.height - textSize.height) / 2;
      case TextVerticalAlign.bottom:
        dy = containerSize.height - textSize.height;
    }

    if (dy.isNaN || dy.isInfinite || dy < 0) {
      dy = 0;
    }

    return Offset(0, dy);
  }

  bool _shouldPaintSerialConnectors({
    required Set<String> boundTextIds,
    required Map<String, ElementState> previewElementsById,
    required Set<String> visibleTextIds,
  }) {
    for (final textId in visibleTextIds) {
      if (boundTextIds.contains(textId)) {
        return true;
      }
    }
    for (final previewElement in previewElementsById.values) {
      final data = previewElement.data;
      if (data is SerialNumberData &&
          data.textElementId != null &&
          data.textElementId!.isNotEmpty &&
          visibleTextIds.contains(data.textElementId)) {
        return true;
      }
    }
    return false;
  }

  DrawPoint? _resolveHandlePositionFromHandles(
    List<ArrowPointHandle> handles,
    ArrowPointHandle handle,
  ) {
    for (final candidate in handles) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    return null;
  }

  Offset _localOffset(DrawRect rect, DrawPoint point) =>
      Offset(point.x - rect.minX, point.y - rect.minY);

  /// Draw box-selection overlay.
  void _drawBoxSelection(
    Canvas canvas,
    DrawRect bounds,
    double scale,
    BoxSelectionConfig boxSelectionConfig,
  ) {
    // Draw translucent fill.
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = boxSelectionConfig.fillColor
          .withValues(alpha: boxSelectionConfig.fillOpacity)
          .toFlutterColor();

    // Draw stroke.
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = boxSelectionConfig.strokeWidth / scale
      ..color = boxSelectionConfig.strokeColor.toFlutterColor()
      ..isAntiAlias = true;
    canvas
      ..save()
      ..drawRect(
        Rect.fromLTWH(bounds.minX, bounds.minY, bounds.width, bounds.height),
        fillPaint,
      )
      ..drawRect(
        Rect.fromLTWH(bounds.minX, bounds.minY, bounds.width, bounds.height),
        strokePaint,
      )
      ..restore();
  }

  void _drawSnapGuides({
    required Canvas canvas,
    required List<SnapGuide> guides,
    required SnapConfig config,
    required double scale,
  }) {
    final invScale = 1.0 / scale;
    final strokeWidth = config.lineWidth * invScale;
    final markerSize = config.markerSize * invScale;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = config.lineColor.toFlutterColor()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final drawMarkers = markerSize > 0;

    for (final guide in guides) {
      final start = guide.start;
      final end = guide.end;
      if (start == end) {
        continue;
      }
      final isGap = guide.kind == SnapGuideKind.gap;
      if (isGap) {
        _drawGapGuideLine(
          canvas: canvas,
          guide: guide,
          markerSize: markerSize,
          paint: paint,
        );
      } else {
        canvas.drawLine(Offset(start.x, start.y), Offset(end.x, end.y), paint);
      }

      if (isGap && drawMarkers) {
        _drawGapCenterTicks(
          canvas: canvas,
          guide: guide,
          size: markerSize,
          paint: paint,
        );
      }

      if (drawMarkers) {
        if (guide.markers.isEmpty) {
          if (isGap) {
            _drawTick(
              canvas: canvas,
              point: start,
              axis: guide.axis,
              size: markerSize * 1.5,
              paint: paint,
            );
            _drawTick(
              canvas: canvas,
              point: end,
              axis: guide.axis,
              size: markerSize * 1.5,
              paint: paint,
            );
          } else {
            _drawCross(
              canvas: canvas,
              point: start,
              size: markerSize,
              paint: paint,
            );
            _drawCross(
              canvas: canvas,
              point: end,
              size: markerSize,
              paint: paint,
            );
          }
        } else {
          for (final marker in guide.markers) {
            if (isGap) {
              final isEndMarker = marker == start || marker == end;
              _drawTick(
                canvas: canvas,
                point: marker,
                axis: guide.axis,
                size: isEndMarker ? markerSize * 1.5 : markerSize,
                paint: paint,
              );
            } else {
              _drawCross(
                canvas: canvas,
                point: marker,
                size: markerSize,
                paint: paint,
              );
            }
          }
        }
      }

      if (isGap && config.showGapSize && guide.label != null) {
        _drawGapLabel(
          canvas: canvas,
          guide: guide,
          scale: scale,
          color: config.lineColor.toFlutterColor(),
        );
      }
    }
  }

  void _drawGapCenterTicks({
    required Canvas canvas,
    required SnapGuide guide,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final start = guide.start;
    final end = guide.end;
    final midX = (start.x + end.x) / 2;
    final midY = (start.y + end.y) / 2;
    final separation = size * 0.6;
    if (guide.axis == SnapGuideAxis.horizontal) {
      _drawTick(
        canvas: canvas,
        point: DrawPoint(x: midX - separation / 2, y: midY),
        axis: guide.axis,
        size: size,
        paint: paint,
      );
      _drawTick(
        canvas: canvas,
        point: DrawPoint(x: midX + separation / 2, y: midY),
        axis: guide.axis,
        size: size,
        paint: paint,
      );
      return;
    }
    _drawTick(
      canvas: canvas,
      point: DrawPoint(x: midX, y: midY - separation / 2),
      axis: guide.axis,
      size: size,
      paint: paint,
    );
    _drawTick(
      canvas: canvas,
      point: DrawPoint(x: midX, y: midY + separation / 2),
      axis: guide.axis,
      size: size,
      paint: paint,
    );
  }

  void _drawGapGuideLine({
    required Canvas canvas,
    required SnapGuide guide,
    required double markerSize,
    required Paint paint,
  }) {
    final start = guide.start;
    final end = guide.end;
    if (guide.axis == SnapGuideAxis.horizontal) {
      final y = (start.y + end.y) / 2;
      final minX = math.min(start.x, end.x);
      final maxX = math.max(start.x, end.x);
      if (markerSize > 0) {
        final midX = (minX + maxX) / 2;
        final separation = markerSize * 0.6;
        final gapPadding = math.max(paint.strokeWidth, markerSize * 0.15);
        final gapStart = midX - separation / 2 - gapPadding;
        final gapEnd = midX + separation / 2 + gapPadding;
        if (gapStart > minX) {
          canvas.drawLine(Offset(minX, y), Offset(gapStart, y), paint);
        }
        if (gapEnd < maxX) {
          canvas.drawLine(Offset(gapEnd, y), Offset(maxX, y), paint);
        }
        return;
      }
      canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
      return;
    }

    final x = (start.x + end.x) / 2;
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    if (markerSize > 0) {
      final midY = (minY + maxY) / 2;
      final separation = markerSize * 0.6;
      final gapPadding = math.max(paint.strokeWidth, markerSize * 0.15);
      final gapStart = midY - separation / 2 - gapPadding;
      final gapEnd = midY + separation / 2 + gapPadding;
      if (gapStart > minY) {
        canvas.drawLine(Offset(x, minY), Offset(x, gapStart), paint);
      }
      if (gapEnd < maxY) {
        canvas.drawLine(Offset(x, gapEnd), Offset(x, maxY), paint);
      }
      return;
    }
    canvas.drawLine(Offset(x, minY), Offset(x, maxY), paint);
  }

  void _drawCross({
    required Canvas canvas,
    required DrawPoint point,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final half = size * 0.35;
    final x = point.x;
    final y = point.y;
    canvas
      ..drawLine(Offset(x - half, y - half), Offset(x + half, y + half), paint)
      ..drawLine(Offset(x - half, y + half), Offset(x + half, y - half), paint);
  }

  void _drawTick({
    required Canvas canvas,
    required DrawPoint point,
    required SnapGuideAxis axis,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final half = size / 2;
    if (axis == SnapGuideAxis.horizontal) {
      canvas.drawLine(
        Offset(point.x, point.y - half),
        Offset(point.x, point.y + half),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(point.x - half, point.y),
        Offset(point.x + half, point.y),
        paint,
      );
    }
  }

  void _drawGapLabel({
    required Canvas canvas,
    required SnapGuide guide,
    required double scale,
    required Color color,
  }) {
    final label = guide.label;
    if (label == null) {
      return;
    }
    final textPainter = _gapLabelPainter
      ..text = TextSpan(
        text: label.toStringAsFixed(0),
        style: TextStyle(color: color, fontSize: 10 / scale),
      )
      ..layout();

    final mid = DrawPoint(
      x: (guide.start.x + guide.end.x) / 2,
      y: (guide.start.y + guide.end.y) / 2,
    );
    final offset = Offset(
      mid.x - textPainter.width / 2,
      mid.y - textPainter.height - (4 / scale),
    );
    textPainter.paint(canvas, offset);
  }

  void _drawBoxSelectionPreviewElements({
    required Canvas canvas,
    required List<ElementState> elements,
    required SelectionConfig selectionConfig,
    required double scale,
  }) {
    if (elements.isEmpty) {
      return;
    }

    for (final element in elements) {
      if (element.data is FreeDrawData) {
        _drawFreeDrawSelectionPreview(
          canvas: canvas,
          element: element,
          selectionConfig: selectionConfig,
          scale: scale,
        );
        continue;
      }
      elementRenderer.renderSelectionOutline(
        canvas: canvas,
        bounds: element.rect,
        scaleFactor: scale,
        config: selectionConfig,
        rotation: element.rotation,
        rotationCenter: element.center,
        dashed: false,
      );
    }
  }

  void _drawFreeDrawSelectionPreview({
    required Canvas canvas,
    required ElementState element,
    required SelectionConfig selectionConfig,
    required double scale,
  }) {
    _drawFreeDrawOutline(
      canvas: canvas,
      element: element,
      scale: scale,
      color: selectionConfig.render.strokeColor.toFlutterColor(),
    );
  }

  @override
  bool shouldRepaint(covariant SceneCanvasPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneCanvasPainter && other.renderKey == renderKey;

  @override
  int get hashCode => renderKey.hashCode;
}

class _ArrowOverlayPaints {
  _ArrowOverlayPaints();

  final addableStroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final addableFill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final addableStrokeHighlighted = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final addableFillHighlighted = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final turningFill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final turningStroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final turningStrokeHighlighted = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final fixedFill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final fixedStroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final fixedStrokeHighlighted = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final hoverOuterFill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final loopStroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final loopStrokeHighlighted = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final deleteStroke = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.redAccent
    ..isAntiAlias = true;

  void configure({
    required double strokeWidth,
    required Color fillColor,
    required Color strokeColor,
    required Color highlightStrokeColor,
  }) {
    addableStroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor.withValues(alpha: 0.35);
    addableFill.color = strokeColor.withValues(alpha: 0.18);
    addableStrokeHighlighted
      ..strokeWidth = strokeWidth
      ..color = strokeColor.withValues(alpha: 0.85);
    addableFillHighlighted.color = strokeColor.withValues(alpha: 0.55);
    turningFill.color = fillColor.withValues(alpha: 0.90);
    turningStroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor;
    turningStrokeHighlighted
      ..strokeWidth = strokeWidth
      ..color = highlightStrokeColor;
    fixedFill.color = fillColor.withValues(alpha: 0.90);
    fixedStroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor.withValues(alpha: 0.9);
    fixedStrokeHighlighted
      ..strokeWidth = strokeWidth
      ..color = highlightStrokeColor;
    hoverOuterFill.color = strokeColor.withValues(alpha: 0.25);
    loopStroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor;
    loopStrokeHighlighted
      ..strokeWidth = strokeWidth
      ..color = highlightStrokeColor;
    deleteStroke.strokeWidth = strokeWidth * 1.4;
  }
}

class _SceneRenderContext {
  const _SceneRenderContext({
    required this.hasFilterElement,
    required this.shouldPaintSerialConnectors,
    required this.serialConnectors,
    required this.volatileElementIds,
    required this.plannedElementTasksById,
  });

  final bool hasFilterElement;
  final bool shouldPaintSerialConnectors;
  final Map<String, List<SerialNumberTextConnector>> serialConnectors;
  final Set<String> volatileElementIds;
  final Map<String, List<RenderTask>> plannedElementTasksById;
}

class _SceneRenderAnalysis {
  _SceneRenderAnalysis({
    required this.hasFilterElement,
    required Set<String> visibleTextIds,
    required this.shouldPaintSerialConnectors,
  }) : visibleTextIds = Set<String>.unmodifiable(visibleTextIds);

  final bool hasFilterElement;
  final Set<String> visibleTextIds;
  final bool shouldPaintSerialConnectors;
}
