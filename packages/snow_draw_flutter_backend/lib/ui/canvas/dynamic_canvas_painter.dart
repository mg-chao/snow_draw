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
import 'highlight_interaction_scene_cache.dart';
import 'highlight_mask_painter.dart';
import 'highlight_mask_static_scene_cache.dart';
import 'render_keys.dart';
import 'serial_number_connection_painter.dart';
import 'watermark_painter.dart';

final ModuleLogger _dynamicCanvasFallbackLog = LogService.fallback.render;

/// Dynamic canvas painter.
///
/// Renders the full document scene and interaction overlays.
///
/// The single-canvas architecture routes all draw content through this painter.
@immutable
class DynamicCanvasPainter extends CustomPainter {
  const DynamicCanvasPainter({
    required this.renderKey,
    required this.stateView,
  });

  static const _directSolidPreviewPointThreshold = 32;
  static final _gapLabelPainter = TextPainter(textDirection: TextDirection.ltr);
  static final _interactionSceneCache = InteractionSceneCache();
  static final _visibleSceneCache = VisibleElementSceneCache();
  static final _highlightMaskStaticSceneCache = HighlightMaskStaticSceneCache();
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
  static _SceneRenderContextCacheEntry? _sceneRenderContextCache;
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
  final DynamicCanvasRenderKey renderKey;

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

  GridConfig _resolveGridConfig(GridRenderTask? task) {
    if (task == null) {
      return renderKey.gridConfig;
    }
    return GridConfig(
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
  }

  HighlightMaskRenderTask? _buildLegacyHighlightMaskTask() {
    final scene = stateView.highlightMaskScene;
    if (!scene.hasHighlights) {
      return null;
    }
    return HighlightMaskRenderTask(
      config: renderKey.highlightMaskConfig,
      highlights: scene.elements,
      staticHighlights: scene.staticElements,
      dynamicHighlights: scene.dynamicElements,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    if (!_isFreeDrawCreationInteraction(state.application.interaction)) {
      _freeDrawPreviewCache.clear();
    }
    final camera = renderKey.camera;
    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;
    final plannedBackgroundTask = _firstPlannedTask<BackgroundRenderTask>();
    final plannedGridTask = _firstPlannedTask<GridRenderTask>();
    final effectiveBackgroundColor =
        plannedBackgroundTask?.color ?? renderKey.canvasConfig.backgroundColor;
    final effectiveGridConfig = _resolveGridConfig(plannedGridTask);
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
    _drawDynamicElements(
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
      _paintDynamicHighlightMask(
        canvas: canvas,
        task: plannedHighlightMaskTask,
        viewportRect: viewportRect,
        scale: scale,
        cameraPosition: Offset(camera.position.x, camera.position.y),
      );
    } else if (renderKey.isHighlightMaskVisible) {
      final legacyHighlightMaskTask = _buildLegacyHighlightMaskTask();
      if (legacyHighlightMaskTask != null) {
        _paintDynamicHighlightMask(
          canvas: canvas,
          task: legacyHighlightMaskTask,
          viewportRect: viewportRect,
          scale: scale,
          cameraPosition: Offset(camera.position.x, camera.position.y),
        );
      } else {
        _highlightMaskStaticSceneCache.clear();
      }
    } else {
      _highlightMaskStaticSceneCache.clear();
    }

    final plannedWatermarkTask = _firstPlannedTask<WatermarkRenderTask>();
    final watermarkConfig = plannedWatermarkTask?.config;
    if (watermarkConfig != null || renderKey.isWatermarkVisible) {
      canvas
        ..save()
        ..scale(1 / scale, 1 / scale)
        ..translate(-camera.position.x, -camera.position.y);
      paintWatermark(
        canvas: canvas,
        viewportSize: size,
        config: watermarkConfig ?? renderKey.watermarkConfig,
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
    } else {
      final snapGuides = renderKey.snapGuides;
      if (snapGuides.isNotEmpty && renderKey.snapConfig.showGuides) {
        _drawSnapGuides(
          canvas: canvas,
          guides: snapGuides,
          config: renderKey.snapConfig,
          scale: scale,
        );
      }
    }

    final plannedHoverTasks = _plannedTasks<HoverOutlineRenderTask>();
    if (plannedHoverTasks.isNotEmpty) {
      for (final task in plannedHoverTasks) {
        _drawHoverOutlineFromTask(canvas: canvas, task: task, scale: scale);
      }
    } else {
      // Draw hover outline when selection is possible.
      final hoveredElementId = renderKey.hoveredElementId;
      if (hoveredElementId != null &&
          !renderKey.selectedIds.contains(hoveredElementId)) {
        final hoveredElement = state.domain.document.getElementById(
          hoveredElementId,
        );
        if (hoveredElement != null) {
          _drawHoverOutlineFromTask(
            canvas: canvas,
            task: HoverOutlineRenderTask(
              element: stateView.effectiveElement(hoveredElement),
              config: renderKey.hoverSelectionConfig,
            ),
            scale: scale,
          );
        }
      }
    }

    final plannedSelectionOutlineTasks =
        _plannedTasks<SelectionOutlineRenderTask>();
    final plannedSelectionControlsTask =
        _firstPlannedTask<SelectionControlsRenderTask>();
    if (plannedSelectionOutlineTasks.isNotEmpty ||
        plannedSelectionControlsTask != null) {
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
    } else {
      // Draw selection overlay.
      final effectiveSelection = renderKey.effectiveSelection;
      if (effectiveSelection.hasSelection) {
        final bounds = effectiveSelection.bounds;
        if (bounds != null) {
          final rotationCenter = effectiveSelection.center ?? bounds.center;

          // Multi-select renders per-element outlines before shared controls.
          final selectedIds = renderKey.selectedIds;
          if (selectedIds.length > 1) {
            for (final element in stateView.selectedElements) {
              final effectiveElement = stateView.effectiveElement(element);
              elementRenderer.renderSelectionOutline(
                canvas: canvas,
                bounds: effectiveElement.rect,
                scaleFactor: scale,
                config: renderKey.selectionConfig,
                rotation: effectiveElement.rotation,
                rotationCenter: effectiveElement.center,
                dashed: false,
              );
            }
          }

          final firstSelectedData = stateView.selectedElements.isNotEmpty
              ? stateView.selectedElements.first.data
              : null;
          final isSingleTwoPointArrow =
              selectedIds.length == 1 &&
              firstSelectedData is ArrowLikeData &&
              firstSelectedData.points.length == 2;
          final isSingleElbowArrow =
              selectedIds.length == 1 &&
              firstSelectedData is ArrowLikeData &&
              firstSelectedData.arrowType == ArrowType.elbow;
          final cornerHandleOffset =
              selectedIds.length == 1 && firstSelectedData is ArrowLikeData
              ? 8.0
              : 0.0;

          if (!isSingleTwoPointArrow) {
            elementRenderer.renderSelection(
              canvas: canvas,
              bounds: bounds,
              scaleFactor: scale,
              config: renderKey.selectionConfig,
              rotation: effectiveSelection.rotation,
              rotationCenter: rotationCenter,
              dashed: selectedIds.length > 1,
              cornerHandleOffset: cornerHandleOffset,
            );
            if (!isSingleElbowArrow) {
              elementRenderer.renderRotationHandle(
                canvas: canvas,
                bounds: bounds,
                scaleFactor: scale,
                config: renderKey.selectionConfig,
                rotation: effectiveSelection.rotation,
                rotationCenter: rotationCenter,
              );
            }
          }
        }
      }

      if (renderKey.selectedIds.length == 1) {
        final selectedId = renderKey.selectedIds.first;
        final element = state.domain.document.getElementById(selectedId);
        if (element?.data is TextData) {
          final effectiveElement = stateView.effectiveElement(element!);
          elementRenderer.renderSelectionOutline(
            canvas: canvas,
            bounds: effectiveElement.rect,
            scaleFactor: scale,
            config: renderKey.hoverSelectionConfig,
            rotation: effectiveElement.rotation,
            rotationCenter: effectiveElement.center,
          );
        }
      }
    }

    _drawArrowBindingHighlight(canvas: canvas, scale: scale);

    final plannedArrowOverlayTask =
        _firstPlannedTask<ArrowPointOverlayRenderTask>();
    if (plannedArrowOverlayTask != null) {
      _drawArrowPointOverlayTask(
        canvas: canvas,
        task: plannedArrowOverlayTask,
        scale: scale,
      );
    } else {
      _drawArrowPointOverlay(canvas: canvas, scale: scale);
    }

    final plannedBoxSelectionTask = _firstPlannedTask<BoxSelectionRenderTask>();
    if (plannedBoxSelectionTask != null) {
      _drawBoxSelectionPreviewElements(
        canvas: canvas,
        elements: plannedBoxSelectionTask.previewElements,
        scale: scale,
      );
      _drawBoxSelection(
        canvas,
        plannedBoxSelectionTask.bounds,
        scale,
        plannedBoxSelectionTask.config,
      );
    } else {
      final boxSelectionBounds = renderKey.boxSelectionBounds;
      if (boxSelectionBounds != null) {
        _drawBoxSelectionPreview(canvas, boxSelectionBounds, scale);
        _drawBoxSelection(
          canvas,
          boxSelectionBounds,
          scale,
          renderKey.boxSelectionConfig,
        );
      }
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
        renderKey.camera.position.x,
        renderKey.camera.position.y,
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

  void _paintDynamicHighlightMask({
    required Canvas canvas,
    required HighlightMaskRenderTask task,
    required DrawRect viewportRect,
    required double scale,
    required Offset cameraPosition,
  }) {
    if (task.highlights.isEmpty) {
      return;
    }

    final highlights = task.highlights;
    final staticHighlights = task.staticHighlights;
    final dynamicHighlights = task.dynamicHighlights;
    final maskConfig = task.config;

    // Dynamic highlight edits should use the same whole-mask composition path
    // as settled frames. The static-mask + modulate-hole optimization can
    // alter overlay content and produce inconsistent highlight colors.
    if (dynamicHighlights.isNotEmpty) {
      _highlightMaskStaticSceneCache.clear();
      paintHighlightMask(
        canvas: canvas,
        highlights: highlights,
        viewportRect: viewportRect,
        maskConfig: maskConfig,
        scaleFactor: scale,
        cameraPosition: cameraPosition,
      );
      return;
    }

    final document = stateView.state.domain.document;
    final excludedDocumentHighlightIds = _resolveExcludedDocumentHighlightIds(
      document: document,
      dynamicHighlights: dynamicHighlights,
      previewElementsById: renderKey.previewElementsById,
    );
    final paintedStatic = _highlightMaskStaticSceneCache.paint(
      canvas: canvas,
      document: document,
      staticHighlights: staticHighlights,
      excludedDocumentHighlightIds: excludedDocumentHighlightIds,
      viewportRect: viewportRect,
      maskConfig: maskConfig,
      scaleFactor: scale,
      cameraPosition: cameraPosition,
    );
    if (paintedStatic) {
      return;
    }
    paintHighlightMask(
      canvas: canvas,
      highlights: highlights,
      viewportRect: viewportRect,
      maskConfig: maskConfig,
      scaleFactor: scale,
      cameraPosition: cameraPosition,
    );
  }

  Set<String> _resolveExcludedDocumentHighlightIds({
    required DocumentState document,
    required List<ElementState> dynamicHighlights,
    required Map<String, ElementState> previewElementsById,
  }) {
    if (dynamicHighlights.isEmpty && previewElementsById.isEmpty) {
      return const <String>{};
    }

    final ids = <String>{};
    for (final highlight in dynamicHighlights) {
      final persisted = document.getElementById(highlight.id);
      if (persisted?.data is HighlightData) {
        ids.add(highlight.id);
      }
    }
    if (previewElementsById.isNotEmpty) {
      for (final entry in previewElementsById.entries) {
        final persisted = document.getElementById(entry.key);
        if (persisted?.data is HighlightData &&
            entry.value.data is! HighlightData) {
          ids.add(entry.key);
        }
      }
    }
    if (ids.isEmpty) {
      return const <String>{};
    }
    return Set<String>.unmodifiable(ids);
  }

  void _drawDynamicElements({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required CreatingElementSnapshot? creatingElement,
  }) {
    final state = stateView.state;
    final document = state.domain.document;
    final baseVisibleElements = _visibleSceneCache.resolve(
      document: document,
      viewportRect: viewportRect,
    );
    final excludedElementId =
        creatingElement != null &&
            document.getElementById(creatingElement.element.id) != null
        ? creatingElement.element.id
        : null;
    if (_tryPaintPreviewFastPath(
      canvas: canvas,
      scale: scale,
      viewportRect: viewportRect,
      creatingElement: creatingElement,
      excludedElementId: excludedElementId,
      baseVisibleElements: baseVisibleElements,
      document: document,
    )) {
      return;
    }

    var effectiveElements = resolveVisibleElementScene(
      document: document,
      viewportRect: viewportRect,
      baseVisibleElements: baseVisibleElements,
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

  bool _tryPaintPreviewFastPath({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required CreatingElementSnapshot? creatingElement,
    required String? excludedElementId,
    required List<ElementState> baseVisibleElements,
    required DocumentState document,
  }) {
    final previewElements = renderKey.previewElementsById;
    if (previewElements.isEmpty || excludedElementId != null) {
      return false;
    }

    final creatingData = creatingElement?.element.data;
    if (creatingData is FilterData) {
      return false;
    }

    if (!_canUsePreviewFastPath(
      baseVisibleElements: baseVisibleElements,
      viewportRect: viewportRect,
      document: document,
    )) {
      return false;
    }

    final sceneContext = _resolveSceneRenderContext(
      elements: baseVisibleElements,
    );
    if (sceneContext.hasFilterElement) {
      return false;
    }

    void paintElement(Canvas sceneCanvas, ElementState element) {
      final effective = previewElements[element.id] ?? element;
      if (!identical(effective, element)) {
        final previewAabb = SelectionCalculator.computeElementWorldAabb(
          effective,
        );
        if (!_rectsIntersect(previewAabb, viewportRect)) {
          return;
        }
      }
      _paintSceneElement(
        canvas: sceneCanvas,
        element: effective,
        scale: scale,
        sceneContext: sceneContext,
      );
    }

    _interactionSceneCache.paint(
      canvas: canvas,
      elements: baseVisibleElements,
      dynamicElementIds: sceneContext.dynamicElementIds,
      documentVersion: renderKey.documentVersion,
      textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
      scaleFactor: scale,
      locale: renderKey.locale,
      paintElement: paintElement,
    );
    return true;
  }

  bool _canUsePreviewFastPath({
    required List<ElementState> baseVisibleElements,
    required DrawRect viewportRect,
    required DocumentState document,
  }) {
    final previewElements = renderKey.previewElementsById;
    if (previewElements.isEmpty) {
      return true;
    }

    for (final preview in previewElements.values) {
      if (document.getElementById(preview.id) == null) {
        return false;
      }
      var isVisibleInBase = false;
      for (final element in baseVisibleElements) {
        if (element.id == preview.id) {
          isVisibleInBase = true;
          break;
        }
      }
      if (isVisibleInBase) {
        continue;
      }
      final previewAabb = SelectionCalculator.computeElementWorldAabb(preview);
      if (_rectsIntersect(previewAabb, viewportRect)) {
        return false;
      }
    }
    return true;
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

    if (_canUseInteractionSceneCache(
      hasFilterElement: sceneContext.hasFilterElement,
      effectiveElements: effectiveElements,
      dynamicElementIds: sceneContext.dynamicElementIds,
    )) {
      _interactionSceneCache.paint(
        canvas: canvas,
        elements: effectiveElements,
        dynamicElementIds: sceneContext.dynamicElementIds,
        documentVersion: renderKey.documentVersion,
        textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
        scaleFactor: scale,
        locale: renderKey.locale,
        paintElement: paintElement,
      );
      return;
    }

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
      dynamicElementIds: sceneContext.dynamicElementIds,
      renderHints: FilterRenderHints(
        interactionPreview: sceneContext.useAggressiveCpuFallback,
        aggressiveCpuFallback: sceneContext.useAggressiveCpuFallback,
      ),
    );
    if (renderKey.performanceMonitoringEnabled) {
      final diagnostics = filterSegmentRenderer.lastDiagnostics;
      if (diagnostics.pictureRecorders > 12 || diagnostics.filterPasses > 6) {
        _dynamicCanvasFallbackLog.warning('Heavy dynamic filter frame', {
          'pictureRecorders': diagnostics.pictureRecorders,
          'saveLayers': diagnostics.saveLayers,
          'filterPasses': diagnostics.filterPasses,
          'batchCount': diagnostics.batchCount,
          'batchCacheHits': diagnostics.batchCacheHits,
          'batchCacheMisses': diagnostics.batchCacheMisses,
          'prefixSceneCacheHits': diagnostics.prefixSceneCacheHits,
          'prefixSceneCacheMisses': diagnostics.prefixSceneCacheMisses,
        });
      }
    }
  }

  _SceneRenderContext _resolveSceneRenderContext({
    required List<ElementState> elements,
  }) {
    final document = stateView.state.domain.document;
    final previewElements = renderKey.previewElementsById;
    final dynamicPreviewIds = _resolveDynamicPreviewElementIds(previewElements);
    final creatingFilterId = _resolveCreatingFilterId();
    final previewTopologyHint = renderKey.previewElementsRevision == null
        ? _PreviewTopologyHint.general
        : _PreviewTopologyHint.stableDocumentBacked;
    final staticContext = _resolveSceneRenderContextStaticData(
      document: document,
      elements: elements,
      previewElementsById: previewElements,
      previewTopologyHint: previewTopologyHint,
    );

    final serialConnectorSnapshot = staticContext.shouldPaintSerialConnectors
        ? resolveSerialNumberConnectorSnapshot(
            stateView,
            previewElementsById: previewElements,
            visibleTextElementIds: staticContext.visibleTextIds,
          )
        : const SerialNumberConnectorSnapshot(
            connectorsByTextId: <String, List<SerialNumberTextConnector>>{},
            dynamicTextElementIds: <String>{},
          );
    final interactionDynamicElementIds = _resolveDynamicElementIds(
      dynamicPreviewIds: dynamicPreviewIds,
      creatingFilterId: creatingFilterId,
      serialConnectorTextIds: serialConnectorSnapshot.dynamicTextElementIds,
    );
    final hasInteractiveFilterElement = _hasSharedElementId(
      interactionDynamicElementIds,
      staticContext.filterElementIds,
    );
    // Keep drag previews visually consistent with settled frames. Reserve
    // fast fallback for explicit high-frequency style mutations only.
    final useAggressiveCpuFallback =
        renderKey.preferFastFilterFallback && staticContext.hasFilterElement;
    final plannedElementTasksById = _resolvePlannedElementTasksById();

    return _SceneRenderContext(
      hasFilterElement: staticContext.hasFilterElement,
      hasInteractiveFilterElement: hasInteractiveFilterElement,
      useAggressiveCpuFallback: useAggressiveCpuFallback,
      shouldPaintSerialConnectors: staticContext.shouldPaintSerialConnectors,
      serialConnectors: serialConnectorSnapshot.connectorsByTextId,
      dynamicElementIds: interactionDynamicElementIds,
      plannedElementTasksById: plannedElementTasksById,
    );
  }

  Map<String, List<RenderTask>> _resolvePlannedElementTasksById() {
    final frameTasks = renderKey.framePlan.tasks;
    if (frameTasks.isEmpty) {
      return const <String, List<RenderTask>>{};
    }

    final tasksById = <String, List<RenderTask>>{};
    for (final task in frameTasks) {
      if (task case ElementRenderTask(:final element)) {
        (tasksById[element.id] ??= <RenderTask>[]).add(task);
      }
    }
    if (tasksById.isEmpty) {
      return const <String, List<RenderTask>>{};
    }
    return <String, List<RenderTask>>{
      for (final entry in tasksById.entries)
        entry.key: List<RenderTask>.unmodifiable(entry.value),
    };
  }

  _SceneRenderContextStaticData _resolveSceneRenderContextStaticData({
    required DocumentState document,
    required List<ElementState> elements,
    required Map<String, ElementState> previewElementsById,
    required _PreviewTopologyHint previewTopologyHint,
  }) {
    // Eraser preview mode only applies document-backed opacity overrides.
    // Once the visible element list is stable, static scene metadata stays
    // valid across frames even as the preview override map grows.
    final cached = _sceneRenderContextCache;
    if (cached != null &&
        cached.matchesFast(
          document: document,
          elements: elements,
          previewElementsById: previewElementsById,
          previewTopologyHint: previewTopologyHint,
        )) {
      return cached.staticData;
    }

    final canReuseElementSignature =
        cached != null &&
        identical(cached.document, document) &&
        identical(cached.elements, elements);
    final canReuseGeneralPreviewStaticData =
        canReuseElementSignature &&
        cached.previewTopologyHint == previewTopologyHint &&
        previewTopologyHint == _PreviewTopologyHint.general &&
        cached.serialPreviewSignature.count == 0 &&
        !_containsSerialPreviewElements(previewElementsById);
    if (canReuseGeneralPreviewStaticData) {
      return cached.staticData;
    }

    final elementSignature = canReuseElementSignature
        ? cached.elementSignature
        : _buildSceneElementStructureSignature(elements);
    final serialPreviewSignature =
        previewTopologyHint == _PreviewTopologyHint.stableDocumentBacked
        ? _SerialPreviewSignature.empty
        : _buildSerialPreviewSignature(previewElementsById);
    if (cached != null &&
        cached.matchesBySignature(
          document: document,
          elementSignature: elementSignature,
          serialPreviewSignature: serialPreviewSignature,
          previewTopologyHint: previewTopologyHint,
        )) {
      return cached.staticData;
    }

    final canHaveSerialConnectors =
        document.boundTextIds.isNotEmpty || serialPreviewSignature.count > 0;
    var hasFilterElement = false;
    final filterElementIds = <String>{};
    final visibleTextIds = <String>{};
    for (final element in elements) {
      if (!hasFilterElement && element.data is FilterData) {
        hasFilterElement = true;
      }
      if (element.data is FilterData) {
        filterElementIds.add(element.id);
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

    final staticData = _SceneRenderContextStaticData(
      hasFilterElement: hasFilterElement,
      filterElementIds: filterElementIds,
      visibleTextIds: visibleTextIds,
      shouldPaintSerialConnectors: shouldPaintSerialConnectors,
    );
    _sceneRenderContextCache = _SceneRenderContextCacheEntry(
      document: document,
      elements: elements,
      previewElementsById: previewElementsById,
      previewTopologyHint: previewTopologyHint,
      elementSignature: elementSignature,
      serialPreviewSignature: serialPreviewSignature,
      staticData: staticData,
    );
    return staticData;
  }

  bool _containsSerialPreviewElements(
    Map<String, ElementState> previewElementsById,
  ) {
    if (previewElementsById.isEmpty) {
      return false;
    }
    for (final preview in previewElementsById.values) {
      if (preview.data is SerialNumberData) {
        return true;
      }
    }
    return false;
  }

  _SceneElementStructureSignature _buildSceneElementStructureSignature(
    List<ElementState> elements,
  ) {
    var hash = 0;
    var filterCount = 0;
    var visibleTextCount = 0;
    for (final element in elements) {
      final data = element.data;
      final isFilter = data is FilterData;
      final isVisibleText = data is TextData && element.opacity > 0;
      if (isFilter) {
        filterCount += 1;
      }
      if (isVisibleText) {
        visibleTextCount += 1;
      }
      final flags = (isFilter ? 1 : 0) | (isVisibleText ? 2 : 0);
      hash ^= Object.hash(element.id, flags);
    }
    return _SceneElementStructureSignature(
      hash: hash,
      elementCount: elements.length,
      filterCount: filterCount,
      visibleTextCount: visibleTextCount,
    );
  }

  _SerialPreviewSignature _buildSerialPreviewSignature(
    Map<String, ElementState> previewElementsById,
  ) {
    if (previewElementsById.isEmpty) {
      return _SerialPreviewSignature.empty;
    }

    var hash = 0;
    var count = 0;
    for (final entry in previewElementsById.entries) {
      final data = entry.value.data;
      if (data is! SerialNumberData) {
        continue;
      }
      hash ^= Object.hash(entry.key, data.textElementId ?? '');
      count += 1;
    }
    return _SerialPreviewSignature(hash: hash, count: count);
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
      domain: FilterRenderCacheDomain.canvas,
      documentVersion: renderKey.documentVersion,
      textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
      scaleKey: (scale * 1000).round(),
      localeTag: localeTag,
    );
  }

  bool _canUseInteractionSceneCache({
    required bool hasFilterElement,
    required List<ElementState> effectiveElements,
    required Set<String> dynamicElementIds,
  }) {
    if (hasFilterElement) {
      return false;
    }

    if (_isHighlightPreviewCacheEligible()) {
      return true;
    }

    if (effectiveElements.length < 2) {
      return false;
    }

    if (dynamicElementIds.isEmpty) {
      return true;
    }

    var visibleDynamicCount = 0;
    for (final element in effectiveElements) {
      if (!dynamicElementIds.contains(element.id)) {
        continue;
      }
      visibleDynamicCount += 1;
      if (visibleDynamicCount >= effectiveElements.length) {
        return false;
      }
    }

    return true;
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

  bool _isHighlightPreviewCacheEligible() {
    final previewElements = renderKey.previewElementsById;
    final creatingElement = renderKey.creatingElement;
    if (previewElements.isEmpty) {
      return creatingElement != null &&
          creatingElement.element.data is HighlightData;
    }

    final document = stateView.state.domain.document;
    for (final preview in previewElements.values) {
      if (preview.data is! HighlightData) {
        return false;
      }
      final persisted = document.getElementById(preview.id);
      if (persisted != null && persisted.data is! HighlightData) {
        return false;
      }
    }
    return true;
  }

  Set<String> _resolveDynamicElementIds({
    required Set<String> dynamicPreviewIds,
    String? creatingFilterId,
    Iterable<String> serialConnectorTextIds = const <String>{},
  }) {
    if (dynamicPreviewIds.isEmpty &&
        creatingFilterId == null &&
        serialConnectorTextIds.isEmpty) {
      return const <String>{};
    }

    final dynamicElementIds = <String>{}..addAll(dynamicPreviewIds);
    if (creatingFilterId != null) {
      dynamicElementIds.add(creatingFilterId);
    }
    dynamicElementIds.addAll(serialConnectorTextIds);
    return dynamicElementIds;
  }

  bool _hasSharedElementId(Set<String> candidateIds, Set<String> filterIds) {
    if (candidateIds.isEmpty || filterIds.isEmpty) {
      return false;
    }
    for (final id in candidateIds) {
      if (filterIds.contains(id)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _resolveDynamicPreviewElementIds(
    Map<String, ElementState> previewElementsById,
  ) {
    final override = renderKey.dynamicPreviewElementIds;
    if (override != null) {
      return override;
    }
    if (previewElementsById.isEmpty) {
      return const <String>{};
    }

    final document = stateView.state.domain.document;
    final dynamicIds = <String>{};
    for (final entry in previewElementsById.entries) {
      final persisted = document.getElementById(entry.key);
      if (persisted == null || !identical(persisted, entry.value)) {
        dynamicIds.add(entry.key);
      }
    }
    return dynamicIds;
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

  bool _rectsIntersect(DrawRect a, DrawRect b) =>
      a.minX <= b.maxX &&
      a.maxX >= b.minX &&
      a.minY <= b.maxY &&
      a.maxY >= b.minY;

  void _drawArrowPointOverlay({required Canvas canvas, required double scale}) {
    if (renderKey.selectedIds.length != 1) {
      return;
    }
    final selectedId = renderKey.selectedIds.first;
    final element = stateView.state.domain.document.getElementById(selectedId);
    if (element == null || element.data is! ArrowLikeData) {
      return;
    }

    final effectiveElement = stateView.effectiveElement(element);
    final selectionConfig = renderKey.selectionConfig;
    final handleTolerance = selectionConfig.interaction.handleTolerance / scale;
    final loopThreshold = handleTolerance * 1.5;
    final baseHandleSize = selectionConfig.render.controlPointSize / scale;
    final handleSize = baseHandleSize * ConfigDefaults.arrowPointSizeMultiplier;
    final overlay = ArrowPointUtils.buildOverlay(
      element: effectiveElement,
      loopThreshold: loopThreshold,
      handleSize: handleSize,
    );
    if (overlay.turningPoints.isEmpty &&
        overlay.addablePoints.isEmpty &&
        overlay.loopPoints.isEmpty) {
      return;
    }
    _drawArrowPointHandles(
      canvas: canvas,
      element: effectiveElement,
      handles: <ArrowPointHandle>[
        ...overlay.addablePoints,
        ...overlay.turningPoints,
        ...overlay.loopPoints,
      ],
      selectionConfig: selectionConfig,
      activeHandle: renderKey.activeArrowHandle,
      hoveredHandle: renderKey.hoveredArrowHandle,
      deleteIndicatorVisible: renderKey.arrowDeleteIndicatorVisible,
      scale: scale,
    );
  }

  void _drawArrowBindingHighlight({
    required Canvas canvas,
    required double scale,
  }) {
    final highlights = _resolveArrowBindingHighlights();
    if (highlights.isEmpty) {
      return;
    }
    final strokeColor = renderKey.selectionConfig.render.strokeColor
        .toFlutterColor();
    final paint = createBindingHighlightPaint(color: strokeColor, scale: scale);

    for (final highlight in highlights) {
      final element = stateView.state.domain.document.getElementById(
        highlight.elementId,
      );
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

  List<_ArrowBindingHighlight> _resolveArrowBindingHighlights() {
    final highlights = <_ArrowBindingHighlight>[];
    final hoveredBindingElementId = resolveHoverBindingHighlightId(
      hoveredBindingElementId: renderKey.hoveredBindingElementId,
      hoveredArrowHandle: renderKey.hoveredArrowHandle,
    );
    if (hoveredBindingElementId != null) {
      highlights.add(
        _ArrowBindingHighlight(elementId: hoveredBindingElementId),
      );
    }

    final interaction = stateView.state.application.interaction;
    if (interaction is EditingState &&
        interaction.context is ArrowPointEditContext) {
      final context = interaction.context as ArrowPointEditContext;
      final element = stateView.state.domain.document.getElementById(
        context.elementId,
      );
      if (element != null && element.data is ArrowLikeData) {
        final effectiveElement = stateView.effectiveElement(element);
        final data = effectiveElement.data as ArrowLikeData;
        final binding = resolveArrowPointEditHighlightBinding(
          context: context,
          data: data,
          transform: interaction.currentTransform,
        );
        final highlight = _highlightFromBinding(binding);
        if (highlight != null) {
          highlights.add(highlight);
        }
      }
    } else if (interaction is CreatingState && interaction.isPointCreation) {
      final element = interaction.element;
      final data = element.data;
      if (data is ArrowLikeData) {
        final endHighlight = _highlightFromBinding(data.endBinding);
        if (endHighlight != null) {
          highlights.add(endHighlight);
        }
        final startHighlight = _highlightFromBinding(data.startBinding);
        if (startHighlight != null) {
          highlights.add(startHighlight);
        }
      }
    }

    return _dedupeArrowBindingHighlights(highlights);
  }

  List<_ArrowBindingHighlight> _dedupeArrowBindingHighlights(
    List<_ArrowBindingHighlight> highlights,
  ) {
    if (highlights.isEmpty) {
      return const <_ArrowBindingHighlight>[];
    }
    final unique = <String, _ArrowBindingHighlight>{
      for (final highlight in highlights) highlight.elementId: highlight,
    };
    return unique.values.toList(growable: false);
  }

  _ArrowBindingHighlight? _highlightFromBinding(ArrowBinding? binding) {
    if (binding == null) {
      return null;
    }
    return _ArrowBindingHighlight(elementId: binding.elementId);
  }

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
          scale: scale,
        );
        continue;
      }
      elementRenderer.renderSelectionOutline(
        canvas: canvas,
        bounds: element.rect,
        scaleFactor: scale,
        config: renderKey.selectionConfig,
        rotation: element.rotation,
        rotationCenter: element.center,
        dashed: false,
      );
    }
  }

  /// Draw preview borders for elements that would be selected.
  void _drawBoxSelectionPreview(Canvas canvas, DrawRect bounds, double scale) {
    final state = stateView.state;
    final document = state.domain.document;
    final candidates = document.getElementsInRect(bounds);

    for (final element in candidates) {
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      // Show preview for elements that overlap the selection bounds.
      if (bounds.minX <= aabb.maxX &&
          bounds.maxX >= aabb.minX &&
          bounds.minY <= aabb.maxY &&
          bounds.maxY >= aabb.minY) {
        // Draw preview border using same style as multi-select outlines
        final effectiveElement = stateView.effectiveElement(element);
        if (effectiveElement.data is FreeDrawData) {
          _drawFreeDrawSelectionPreview(
            canvas: canvas,
            element: effectiveElement,
            scale: scale,
          );
        } else {
          elementRenderer.renderSelectionOutline(
            canvas: canvas,
            bounds: effectiveElement.rect,
            scaleFactor: scale,
            config: renderKey.selectionConfig,
            rotation: effectiveElement.rotation,
            rotationCenter: effectiveElement.center,
            dashed: false,
          );
        }
      }
    }
  }

  void _drawFreeDrawSelectionPreview({
    required Canvas canvas,
    required ElementState element,
    required double scale,
  }) {
    _drawFreeDrawOutline(
      canvas: canvas,
      element: element,
      scale: scale,
      color: renderKey.selectionConfig.render.strokeColor.toFlutterColor(),
    );
  }

  @override
  bool shouldRepaint(covariant DynamicCanvasPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicCanvasPainter && other.renderKey == renderKey;

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

class _ArrowBindingHighlight {
  const _ArrowBindingHighlight({required this.elementId});

  final String elementId;
}

enum _PreviewTopologyHint { general, stableDocumentBacked }

class _SceneRenderContext {
  const _SceneRenderContext({
    required this.hasFilterElement,
    required this.hasInteractiveFilterElement,
    required this.useAggressiveCpuFallback,
    required this.shouldPaintSerialConnectors,
    required this.serialConnectors,
    required this.dynamicElementIds,
    required this.plannedElementTasksById,
  });

  final bool hasFilterElement;
  final bool hasInteractiveFilterElement;
  final bool useAggressiveCpuFallback;
  final bool shouldPaintSerialConnectors;
  final Map<String, List<SerialNumberTextConnector>> serialConnectors;
  final Set<String> dynamicElementIds;
  final Map<String, List<RenderTask>> plannedElementTasksById;
}

class _SceneRenderContextStaticData {
  _SceneRenderContextStaticData({
    required this.hasFilterElement,
    required Set<String> filterElementIds,
    required Set<String> visibleTextIds,
    required this.shouldPaintSerialConnectors,
  }) : filterElementIds = Set<String>.unmodifiable(filterElementIds),
       visibleTextIds = Set<String>.unmodifiable(visibleTextIds);

  final bool hasFilterElement;
  final Set<String> filterElementIds;
  final Set<String> visibleTextIds;
  final bool shouldPaintSerialConnectors;
}

class _SceneRenderContextCacheEntry {
  _SceneRenderContextCacheEntry({
    required this.document,
    required this.elements,
    required this.previewElementsById,
    required this.previewTopologyHint,
    required this.elementSignature,
    required this.serialPreviewSignature,
    required this.staticData,
  });

  final DocumentState document;
  final List<ElementState> elements;
  final Map<String, ElementState> previewElementsById;
  final _PreviewTopologyHint previewTopologyHint;
  final _SceneElementStructureSignature elementSignature;
  final _SerialPreviewSignature serialPreviewSignature;
  final _SceneRenderContextStaticData staticData;

  bool matchesFast({
    required DocumentState document,
    required List<ElementState> elements,
    required Map<String, ElementState> previewElementsById,
    required _PreviewTopologyHint previewTopologyHint,
  }) =>
      identical(this.document, document) &&
      identical(this.elements, elements) &&
      this.previewTopologyHint == previewTopologyHint &&
      (previewTopologyHint == _PreviewTopologyHint.stableDocumentBacked ||
          identical(this.previewElementsById, previewElementsById));

  bool matchesBySignature({
    required DocumentState document,
    required _SceneElementStructureSignature elementSignature,
    required _SerialPreviewSignature serialPreviewSignature,
    required _PreviewTopologyHint previewTopologyHint,
  }) =>
      identical(this.document, document) &&
      this.previewTopologyHint == previewTopologyHint &&
      this.elementSignature == elementSignature &&
      this.serialPreviewSignature == serialPreviewSignature;
}

@immutable
class _SceneElementStructureSignature {
  const _SceneElementStructureSignature({
    required this.hash,
    required this.elementCount,
    required this.filterCount,
    required this.visibleTextCount,
  });

  final int hash;
  final int elementCount;
  final int filterCount;
  final int visibleTextCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SceneElementStructureSignature &&
          other.hash == hash &&
          other.elementCount == elementCount &&
          other.filterCount == filterCount &&
          other.visibleTextCount == visibleTextCount;

  @override
  int get hashCode =>
      Object.hash(hash, elementCount, filterCount, visibleTextCount);
}

@immutable
class _SerialPreviewSignature {
  const _SerialPreviewSignature({required this.hash, required this.count});

  static const empty = _SerialPreviewSignature(hash: 0, count: 0);

  final int hash;
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SerialPreviewSignature &&
          other.hash == hash &&
          other.count == count;

  @override
  int get hashCode => Object.hash(hash, count);
}
