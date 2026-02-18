import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/render/element_renderer.dart';
import '../../draw/services/log/log_service.dart';
import '../../draw/types/draw_rect.dart';
import 'filter_scene_compositor.dart';
import 'grid_shader_painter.dart';
import 'highlight_mask_painter.dart';
import 'highlight_mask_visibility.dart';
import 'render_keys.dart';
import 'serial_number_connection_painter.dart';
import 'visible_element_scene_resolver.dart';

final ModuleLogger _staticCanvasFallbackLog = LogService.fallback.render;

/// Static canvas painter.
///
/// Renders persistent elements with viewport culling.
/// This layer should be wrapped in a RepaintBoundary to avoid unnecessary
/// repaints.
@immutable
class StaticCanvasPainter extends CustomPainter {
  const StaticCanvasPainter({required this.renderKey, required this.stateView});

  /// Render key for precise repaint decisions.
  final StaticCanvasRenderKey renderKey;

  /// Precomputed effective state view (needed for paint).
  final DrawStateView stateView;

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    final document = state.domain.document;
    final camera = renderKey.camera;
    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;
    final interaction = state.application.interaction;
    final creatingElementId = interaction is CreatingState
        ? interaction.elementId
        : null;
    final previewElements = creatingElementId == null
        ? renderKey.previewElementsById
        : const <String, ElementState>{};
    final dynamicLayerStartIndex = renderKey.dynamicLayerStartIndex;
    final skipBaseElementScene = renderKey.skipBaseElementScene;

    // Draw background.
    _drawBackground(canvas, size);

    // Calculate viewport in world coordinates.
    // Viewport is (0,0) to (width, height) in screen coordinates.
    // Transform to world: (screen - translate) / scale
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    // Try GPU-accelerated shader grid first (drawn in screen coordinates).
    final shaderUsed = _drawGridWithShader(canvas, size, scale);

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    // Fall back to CPU-based grid if shader not available.
    if (!shaderUsed) {
      _drawGridFallback(canvas, viewportRect, scale);
    }

    if (!skipBaseElementScene) {
      final maxOrderIndex = dynamicLayerStartIndex == null
          ? null
          : dynamicLayerStartIndex - 1;
      final effectiveElements = resolveVisibleElementScene(
        document: document,
        viewportRect: viewportRect,
        previewElementsById: previewElements,
        maxOrderIndex: maxOrderIndex,
        excludedElementId: creatingElementId,
      );

      var hasFilterElement = false;
      final visibleTextIds = <String>{};
      for (final element in effectiveElements) {
        if (!hasFilterElement && element.data is FilterData) {
          hasFilterElement = true;
        }
        if (element.opacity > 0 && element.data is TextData) {
          visibleTextIds.add(element.id);
        }
      }
      _includeEditingTextIdForSerialConnectors(
        stateView: stateView,
        previewElementsById: previewElements,
        visibleTextIds: visibleTextIds,
      );
      final shouldPaintSerialConnectors =
          visibleTextIds.isNotEmpty &&
          _shouldPaintSerialConnectors(
            boundTextIds: document.boundTextIds,
            previewElementsById: previewElements,
            visibleTextIds: visibleTextIds,
          );
      final serialConnectors = shouldPaintSerialConnectors
          ? resolveSerialNumberConnectorMap(
              stateView,
              previewElementsById: previewElements,
              visibleTextElementIds: visibleTextIds,
            )
          : const <String, List<SerialNumberTextConnector>>{};
      void paintElement(Canvas sceneCanvas, ElementState element) {
        elementRenderer.renderElement(
          canvas: sceneCanvas,
          element: element,
          scaleFactor: scale,
          registry: renderKey.elementRegistry,
          locale: renderKey.locale,
        );
        if (shouldPaintSerialConnectors) {
          drawSerialNumberConnectorsForText(
            canvas: sceneCanvas,
            textElement: element,
            connectorsByTextId: serialConnectors,
          );
        }
      }

      if (!hasFilterElement) {
        for (final element in effectiveElements) {
          paintElement(canvas, element);
        }
      } else {
        final filterCacheContext = shouldPaintSerialConnectors
            ? null
            : _buildFilterCacheContext(scale: scale);
        filterSceneCompositor.paintElements(
          canvas: canvas,
          elements: effectiveElements,
          cacheContext: filterCacheContext,
          visibleBounds: Rect.fromLTWH(
            viewportRect.minX,
            viewportRect.minY,
            viewportRect.width,
            viewportRect.height,
          ),
          paintElement: paintElement,
        );
        if (renderKey.performanceMonitoringEnabled) {
          final diagnostics = filterSceneCompositor.lastDiagnostics;
          if (diagnostics.pictureRecorders > 12 ||
              diagnostics.filterPasses > 6) {
            _staticCanvasFallbackLog.warning('Heavy static filter frame', {
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
    }

    if (renderKey.highlightMaskLayer == HighlightMaskLayer.staticLayer) {
      paintHighlightMask(
        canvas: canvas,
        highlights: stateView.highlightMaskScene.elements,
        viewportRect: viewportRect,
        maskConfig: renderKey.highlightMaskConfig,
        scaleFactor: scale,
        cameraPosition: Offset(camera.position.x, camera.position.y),
      );
    }

    canvas.restore();
  }

  /// Draw background.
  ///
  /// Reuses a cached [Paint] when the background color hasn't changed
  /// to avoid a native allocation on every frame.
  void _drawBackground(Canvas canvas, Size size) {
    final color = renderKey.canvasConfig.backgroundColor;
    final paint = _resolveBackgroundPaint(color);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  static Paint? _cachedBackgroundPaint;
  static Color? _cachedBackgroundColor;
  static final _minorGridPaint = Paint()..style = PaintingStyle.stroke;
  static final _majorGridPaint = Paint()..style = PaintingStyle.stroke;
  static var _minorGridPointBuffer = Float32List(0);
  static var _majorGridPointBuffer = Float32List(0);

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

  /// Draws the grid using the GPU-accelerated fragment shader.
  ///
  /// Returns true if the shader was used successfully, false if fallback
  /// rendering should be used instead.
  bool _drawGridWithShader(Canvas canvas, Size size, double scale) {
    final config = renderKey.gridConfig;
    if (!config.enabled) {
      return true; // Grid disabled, no need for fallback.
    }

    final baseSize = config.size;
    if (baseSize <= 0) {
      return true; // Invalid config, no need for fallback.
    }

    final effectiveScale = scale == 0 ? 1.0 : scale;
    if (baseSize * effectiveScale < config.minRenderSpacing) {
      return true; // Grid too small to render, no need for fallback.
    }

    final shaderManager = GridShaderManager.instance;
    if (!shaderManager.isReady) {
      return false; // Shader not ready, use fallback.
    }

    final minorOpacityRatio = _resolveMinorOpacityRatio(
      baseSize: baseSize,
      scale: effectiveScale,
      minScreenSpacing: config.minScreenSpacing,
    );
    final majorEveryFactor = _resolveMajorEveryFactor(
      baseSize: baseSize,
      majorEvery: config.majorLineEvery,
      scale: effectiveScale,
      minSpacing: config.minScreenSpacing,
    );

    return shaderManager.paintGrid(
      canvas: canvas,
      size: size,
      cameraPosition: Offset(
        renderKey.camera.position.x,
        renderKey.camera.position.y,
      ),
      scale: effectiveScale,
      config: config,
      minorOpacityRatio: minorOpacityRatio,
      majorEveryFactor: majorEveryFactor,
    );
  }

  /// Fallback grid rendering using CPU-based drawRawPoints.
  ///
  /// Used when the fragment shader is not available.
  void _drawGridFallback(Canvas canvas, DrawRect viewportRect, double scale) {
    final config = renderKey.gridConfig;
    if (!config.enabled) {
      return;
    }

    final baseSize = config.size;
    if (baseSize <= 0) {
      return;
    }

    final effectiveScale = scale == 0 ? 1.0 : scale;
    if (baseSize * effectiveScale < config.minRenderSpacing) {
      return;
    }

    final minorStrokeWidth = config.lineWidth / effectiveScale;
    // Major lines are 1.5x thicker for clear visual distinction.
    final majorStrokeWidth = minorStrokeWidth * 1.5;
    final screenSpacing = baseSize * effectiveScale;
    final showMinorLines = screenSpacing >= config.minScreenSpacing;
    final minorOpacityRatio = _resolveMinorOpacityRatio(
      baseSize: baseSize,
      scale: effectiveScale,
      minScreenSpacing: config.minScreenSpacing,
    );
    final majorEveryFactor = _resolveMajorEveryFactor(
      baseSize: baseSize,
      majorEvery: config.majorLineEvery,
      scale: effectiveScale,
      minSpacing: config.minScreenSpacing,
    );
    final majorStep = baseSize * majorEveryFactor;

    // Use solid lines with opacity and thickness differentiation for clear
    // visual distinction between major and minor grid lines.
    // Minor lines use reduced opacity (0.5x) for subtlety.
    final minorColor = config.lineColor.withValues(
      alpha: config.lineOpacity * minorOpacityRatio * 0.5,
    );
    final majorColor = config.lineColor.withValues(
      alpha: config.majorLineOpacity,
    );
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

      // Count major vs minor lines for pre-allocation.
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

      // Reuse typed-data buffers to avoid per-frame allocations.
      // Each line needs 4 floats: x1, y1, x2, y2.
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

      // Batch vertical lines.
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

      // Batch horizontal lines.
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

      // Draw all lines with just 2 GPU draw calls.
      if (minorIdx > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          _slicePointBuffer(minorPoints, minorIdx),
          minorPaint,
        );
      }
      if (majorIdx > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          _slicePointBuffer(majorPoints, majorIdx),
          majorPaint,
        );
      }
    } else {
      // Only major lines visible at this zoom level.
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

      // Batch vertical major lines.
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * majorStep;
        majorPoints[idx++] = x;
        majorPoints[idx++] = viewportRect.minY;
        majorPoints[idx++] = x;
        majorPoints[idx++] = viewportRect.maxY;
      }

      // Batch horizontal major lines.
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * majorStep;
        majorPoints[idx++] = viewportRect.minX;
        majorPoints[idx++] = y;
        majorPoints[idx++] = viewportRect.maxX;
        majorPoints[idx++] = y;
      }

      // Single GPU draw call for all major lines.
      if (idx > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          _slicePointBuffer(majorPoints, idx),
          majorPaint,
        );
      }
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
    if (scale <= 0 || minSpacing <= 0) {
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

  FilterRenderCacheContext _buildFilterCacheContext({required double scale}) {
    final localeTag = renderKey.locale?.toLanguageTag() ?? '';
    final normalizedScale = scale == 0 ? 1.0 : scale;
    return FilterRenderCacheContext(
      domain: FilterRenderCacheDomain.staticLayer,
      documentVersion: renderKey.documentVersion,
      textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
      scaleKey: (normalizedScale * 1000).round(),
      localeTag: localeTag,
    );
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

  void _includeEditingTextIdForSerialConnectors({
    required DrawStateView stateView,
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

    final persistedElement = stateView.state.domain.document.getElementById(
      editingTextId,
    );
    if (persistedElement?.data is TextData) {
      visibleTextIds.add(editingTextId);
    }
  }

  @override
  bool shouldRepaint(covariant StaticCanvasPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaticCanvasPainter && other.renderKey == renderKey;

  @override
  int get hashCode => renderKey.hashCode;
}
