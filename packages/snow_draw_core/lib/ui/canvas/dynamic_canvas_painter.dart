import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/elements/types/arrow/arrow_binding.dart';
import '../../draw/elements/types/arrow/arrow_like_data.dart';
import '../../draw/elements/types/arrow/arrow_points.dart';
import '../../draw/elements/types/arrow/arrow_visual_cache.dart';
import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/free_draw/free_draw_visual_cache.dart';
import '../../draw/elements/types/highlight/highlight_data.dart';
import '../../draw/elements/types/rectangle/rectangle_data.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/elements/types/text/text_layout.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/render/element_renderer.dart';
import '../../draw/services/log/log_service.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';
import '../../draw/types/snap_guides.dart';
import '../../draw/utils/arrow_binding_highlight.dart';
import '../../draw/utils/binding_highlight_style.dart';
import '../../draw/utils/binding_highlight_visibility.dart';
import '../../draw/utils/selection_calculator.dart';
import 'filter_scene_compositor.dart';
import 'highlight_interaction_scene_cache.dart';
import 'highlight_mask_painter.dart';
import 'highlight_mask_visibility.dart';
import 'optimized_scene_occlusion.dart';
import 'render_keys.dart';
import 'serial_number_connection_painter.dart';
import 'visible_element_scene_cache.dart';
import 'visible_element_scene_resolver.dart';

final ModuleLogger _dynamicCanvasFallbackLog = LogService.fallback.render;

/// Dynamic canvas painter.
///
/// Renders top-layer elements and interaction overlays.
/// This layer updates frequently during user interaction.
@immutable
class DynamicCanvasPainter extends CustomPainter {
  const DynamicCanvasPainter({
    required this.renderKey,
    required this.stateView,
  });

  static final _gapLabelPainter = TextPainter(textDirection: TextDirection.ltr);
  static final _interactionSceneCache = InteractionSceneCache();
  static final _visibleSceneCache = VisibleElementSceneCache();
  static _SceneRenderContextCacheEntry? _sceneRenderContextCache;
  static final _arrowOverlayPaints = _ArrowOverlayPaints();
  static final _arrowHoverStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// Render key for precise repaint decisions.
  final DynamicCanvasRenderKey renderKey;

  /// Precomputed effective state view (needed for paint).
  final DrawStateView stateView;

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    final camera = renderKey.camera;
    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    final creatingElement = renderKey.creatingElement;

    // Draw elements at or above the selected element to preserve z-order.
    _drawDynamicElements(
      canvas: canvas,
      scale: scale,
      viewportRect: viewportRect,
      creatingElement: creatingElement,
    );

    // Draw creating element preview above the static layer.
    if (creatingElement != null &&
        creatingElement.element.data is! FilterData &&
        !_isFreeDrawCreationInteraction(state.application.interaction)) {
      final previewElement = creatingElement.element.copyWith(
        rect: creatingElement.currentRect,
      );
      elementRenderer.renderElement(
        canvas: canvas,
        element: previewElement,
        scaleFactor: scale,
        registry: renderKey.elementRegistry,
        locale: renderKey.locale,
      );
    }

    if (renderKey.highlightMaskLayer == HighlightMaskLayer.dynamicLayer) {
      paintHighlightMask(
        canvas: canvas,
        highlights: stateView.highlightMaskScene.elements,
        viewportRect: viewportRect,
        maskConfig: renderKey.highlightMaskConfig,
        scaleFactor: scale,
        cameraPosition: Offset(camera.position.x, camera.position.y),
      );
    }

    // Draw snapping guides.
    final snapGuides = renderKey.snapGuides;
    if (snapGuides.isNotEmpty && renderKey.snapConfig.showGuides) {
      _drawSnapGuides(canvas: canvas, guides: snapGuides, scale: scale);
    }

    // Draw hover outline when selection is possible.
    final hoveredElementId = renderKey.hoveredElementId;
    if (hoveredElementId != null &&
        !renderKey.selectedIds.contains(hoveredElementId)) {
      final hoveredElement = state.domain.document.getElementById(
        hoveredElementId,
      );
      if (hoveredElement != null) {
        final effectiveElement = stateView.effectiveElement(hoveredElement);
        // For arrow elements, render an arrow outline instead of a rectangle
        if (effectiveElement.data is ArrowLikeData) {
          _drawArrowHoverOutline(
            canvas: canvas,
            element: effectiveElement,
            scale: scale,
          );
        } else if (effectiveElement.data is TextData) {
          // For text elements, render underlines instead of a rectangle
          _drawTextHoverUnderlines(
            canvas: canvas,
            element: effectiveElement,
            scale: scale,
          );
        } else if (effectiveElement.data is FreeDrawData) {
          _drawFreeDrawHoverOutline(
            canvas: canvas,
            element: effectiveElement,
            scale: scale,
          );
        } else {
          elementRenderer.renderSelectionOutline(
            canvas: canvas,
            bounds: effectiveElement.rect,
            scaleFactor: scale,
            config: renderKey.hoverSelectionConfig,
            rotation: effectiveElement.rotation,
            rotationCenter: effectiveElement.center,
            dashed: false,
          );
        }
      }
    }

    // Draw selection overlay.
    final effectiveSelection = renderKey.effectiveSelection;
    if (effectiveSelection.hasSelection) {
      final bounds = effectiveSelection.bounds;
      if (bounds != null) {
        final rotationCenter = effectiveSelection.center ?? bounds.center;

        // Multi-select: render a per-element outline first (no control points).
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

        // Check if this is a single 2-point arrow selection.
        // For 2-point arrows, skip selection box rendering since all operations
        // can be performed through the point editor.
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

        // Determine corner handle offset for single arrow selections.
        final cornerHandleOffset =
            selectedIds.length == 1 && firstSelectedData is ArrowLikeData
            ? 8.0
            : 0.0;

        // Skip selection box and rotation handle for 2-point arrows.
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

    _drawArrowBindingHighlight(canvas: canvas, scale: scale);
    _drawArrowPointOverlay(canvas: canvas, scale: scale);

    // Draw dashed border for a single selected text element.
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

    // Draw box-selection overlay.
    final boxSelectionBounds = renderKey.boxSelectionBounds;
    if (boxSelectionBounds != null) {
      // Draw preview borders for elements that would be selected
      _drawBoxSelectionPreview(canvas, boxSelectionBounds, scale);
      // Draw the marquee box
      _drawBoxSelection(canvas, boxSelectionBounds, scale);
    }

    canvas.restore();
  }

  bool _isFreeDrawCreationInteraction(InteractionState interaction) =>
      interaction is CreatingState && interaction.elementData is FreeDrawData;

  void _drawDynamicElements({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required CreatingElementSnapshot? creatingElement,
  }) {
    final dynamicLayerStartIndex = renderKey.dynamicLayerStartIndex;
    final rendersWholeScene = renderKey.rendersWholeElementScene;
    final optimizedElementIds = renderKey.optimizedDynamicElementIds;
    final canUseHighlightWholeScenePath = _tryPaintHighlightWholeScenePath(
      canvas: canvas,
      scale: scale,
      viewportRect: viewportRect,
      creatingElement: creatingElement,
      rendersWholeScene: rendersWholeScene,
      optimizedElementIds: optimizedElementIds,
    );
    if (canUseHighlightWholeScenePath) {
      return;
    }

    if (dynamicLayerStartIndex == null && !rendersWholeScene) {
      if (optimizedElementIds.isEmpty) {
        final previewOnlyElements = _resolvePreviewOnlyScene(
          viewportRect: viewportRect,
        );
        _paintElementScene(
          canvas: canvas,
          scale: scale,
          viewportRect: viewportRect,
          effectiveElements: previewOnlyElements,
        );
        return;
      }
      final optimizedElements = _resolveOptimizedScene(
        viewportRect: viewportRect,
        optimizedElementIds: optimizedElementIds,
      );
      _paintElementScene(
        canvas: canvas,
        scale: scale,
        viewportRect: viewportRect,
        effectiveElements: optimizedElements,
      );
      return;
    }

    final state = stateView.state;
    final document = state.domain.document;
    final minOrderIndex = rendersWholeScene
        ? null
        : (dynamicLayerStartIndex ?? 0);
    final baseVisibleElements = _visibleSceneCache.resolve(
      document: document,
      viewportRect: viewportRect,
      minOrderIndex: minOrderIndex,
    );
    final excludedElementId =
        creatingElement != null &&
            document.getElementById(creatingElement.element.id) != null
        ? creatingElement.element.id
        : null;
    var effectiveElements = resolveVisibleElementScene(
      document: document,
      viewportRect: viewportRect,
      baseVisibleElements: baseVisibleElements,
      minOrderIndex: minOrderIndex,
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

  bool _tryPaintHighlightWholeScenePath({
    required Canvas canvas,
    required double scale,
    required DrawRect viewportRect,
    required CreatingElementSnapshot? creatingElement,
    required bool rendersWholeScene,
    required Set<String> optimizedElementIds,
  }) {
    if (!rendersWholeScene ||
        optimizedElementIds.isNotEmpty ||
        !_isHighlightPreviewCacheEligible()) {
      return false;
    }

    final creatingData = creatingElement?.element.data;
    if (creatingData is FilterData) {
      return false;
    }

    final state = stateView.state;
    final document = state.domain.document;
    final baseVisibleElements = _visibleSceneCache.resolve(
      document: document,
      viewportRect: viewportRect,
    );
    if (!_canUseHighlightWholeSceneFastPath(
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
      final effective = renderKey.previewElementsById[element.id] ?? element;
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

  bool _canUseHighlightWholeSceneFastPath({
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

  List<ElementState> _resolvePreviewOnlyScene({
    required DrawRect viewportRect,
  }) {
    final previewElements = renderKey.previewElementsById;
    if (previewElements.isEmpty) {
      return const <ElementState>[];
    }

    final visible = <ElementState>[];
    for (final preview in previewElements.values) {
      if (preview.opacity <= 0) {
        continue;
      }
      final aabb = SelectionCalculator.computeElementWorldAabb(preview);
      if (!_rectsIntersect(aabb, viewportRect)) {
        continue;
      }
      visible.add(preview);
    }
    if (visible.length < 2) {
      return visible;
    }

    final document = stateView.state.domain.document;
    visible.sort((a, b) {
      final orderA = document.getOrderIndex(a.id) ?? a.zIndex;
      final orderB = document.getOrderIndex(b.id) ?? b.zIndex;
      final orderComparison = orderA.compareTo(orderB);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return a.id.compareTo(b.id);
    });
    return visible;
  }

  List<ElementState> _resolveOptimizedScene({
    required DrawRect viewportRect,
    required Set<String> optimizedElementIds,
  }) {
    final document = stateView.state.domain.document;
    if (optimizedElementIds.isEmpty) {
      return const <ElementState>[];
    }

    final previewElementsById = renderKey.previewElementsById;
    final effectiveById = <String, ElementState>{};
    final effectiveAabbsById = <String, DrawRect>{};
    final seedAabbsById = <String, DrawRect>{};
    final seedOrderIndexById = <String, int>{};

    for (final elementId in optimizedElementIds) {
      final effective =
          previewElementsById[elementId] ?? document.getElementById(elementId);
      if (effective == null || effective.opacity <= 0) {
        continue;
      }
      final aabb = SelectionCalculator.computeElementWorldAabb(effective);
      if (!_rectsIntersect(aabb, viewportRect)) {
        continue;
      }
      effectiveById[elementId] = effective;
      effectiveAabbsById[elementId] = aabb;
      seedAabbsById[elementId] = aabb;
      final orderIndex = document.getOrderIndex(elementId);
      if (orderIndex != null) {
        seedOrderIndexById[elementId] = orderIndex;
      }
    }

    if (effectiveById.isEmpty) {
      return const <ElementState>[];
    }

    final orderIndexCache = <String, int?>{};
    int? resolveOrderIndex(String elementId) {
      if (orderIndexCache.containsKey(elementId)) {
        return orderIndexCache[elementId];
      }
      final orderIndex = document.getOrderIndex(elementId);
      orderIndexCache[elementId] = orderIndex;
      return orderIndex;
    }

    DrawRect resolveAabb(ElementState element) {
      final cached = effectiveAabbsById[element.id];
      if (cached != null) {
        return cached;
      }
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      effectiveAabbsById[element.id] = aabb;
      return aabb;
    }

    for (final entry in seedAabbsById.entries) {
      final seedElement = effectiveById[entry.key];
      final seedOrderIndex = seedOrderIndexById[entry.key];
      if (seedElement == null || seedOrderIndex == null) {
        continue;
      }
      final queryRects = resolveOptimizedOccluderQueryRects(
        seedElement: seedElement,
        seedAabb: entry.value,
      );
      for (final queryRect in queryRects) {
        document.visitElementsInRect(queryRect, (element) {
          final elementId = element.id;
          if (optimizedElementIds.contains(elementId)) {
            return true;
          }
          if (effectiveById.containsKey(elementId)) {
            return true;
          }
          final orderIndex = resolveOrderIndex(elementId);
          if (orderIndex == null || orderIndex <= seedOrderIndex) {
            return true;
          }
          final effective = previewElementsById[elementId] ?? element;
          if (effective.opacity <= 0) {
            return true;
          }
          final aabb = resolveAabb(effective);
          if (!_rectsIntersect(aabb, queryRect) ||
              !_rectsIntersect(aabb, viewportRect)) {
            return true;
          }
          effectiveById[elementId] = effective;
          return true;
        });
      }
    }

    final optimized = effectiveById.values.toList(growable: false);
    if (optimized.length < 2) {
      return optimized;
    }

    optimized.sort((a, b) {
      final orderA = resolveOrderIndex(a.id) ?? a.zIndex;
      final orderB = resolveOrderIndex(b.id) ?? b.zIndex;
      final orderComparison = orderA.compareTo(orderB);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return a.id.compareTo(b.id);
    });
    return optimized;
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
    filterSceneCompositor.paintElements(
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
        interactionPreview: sceneContext.hasDynamicFilterElement,
      ),
    );
    if (renderKey.performanceMonitoringEnabled) {
      final diagnostics = filterSceneCompositor.lastDiagnostics;
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
    final selectedFilterIds = _resolveSelectedFilterDynamicIds(
      document: document,
      previewElementsById: previewElements,
    );
    final serialConnectorPreviewElements =
        _extractSerialConnectorPreviewElements(previewElements);
    final cached = _sceneRenderContextCache;
    if (cached != null &&
        cached.matches(
          document: document,
          elements: elements,
          dynamicPreviewIds: dynamicPreviewIds,
          creatingFilterId: creatingFilterId,
          selectedFilterIds: selectedFilterIds,
          serialConnectorPreviewElements: serialConnectorPreviewElements,
        )) {
      return cached.context;
    }

    final canHaveSerialConnectors =
        document.boundTextIds.isNotEmpty ||
        serialConnectorPreviewElements.isNotEmpty;

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

    final shouldPaintSerialConnectors =
        visibleTextIds.isNotEmpty &&
        _shouldPaintSerialConnectors(
          boundTextIds: document.boundTextIds,
          previewElementsById: previewElements,
          visibleTextIds: visibleTextIds,
        );
    final serialConnectorSnapshot = shouldPaintSerialConnectors
        ? resolveSerialNumberConnectorSnapshot(
            stateView,
            previewElementsById: previewElements,
            visibleTextElementIds: visibleTextIds,
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
    final dynamicElementIds = _mergeDynamicElementIds(
      baseDynamicIds: interactionDynamicElementIds,
      additionalDynamicIds: selectedFilterIds,
    );
    var hasDynamicFilterElement = false;
    if (interactionDynamicElementIds.isNotEmpty &&
        filterElementIds.isNotEmpty) {
      for (final dynamicId in interactionDynamicElementIds) {
        if (!filterElementIds.contains(dynamicId)) {
          continue;
        }
        hasDynamicFilterElement = true;
        break;
      }
    }

    final context = _SceneRenderContext(
      hasFilterElement: hasFilterElement,
      hasDynamicFilterElement: hasDynamicFilterElement,
      shouldPaintSerialConnectors: shouldPaintSerialConnectors,
      serialConnectors: serialConnectorSnapshot.connectorsByTextId,
      dynamicElementIds: dynamicElementIds,
    );
    _sceneRenderContextCache = _SceneRenderContextCacheEntry(
      document: document,
      elements: elements,
      dynamicPreviewIds: dynamicPreviewIds,
      creatingFilterId: creatingFilterId,
      selectedFilterIds: selectedFilterIds,
      serialConnectorPreviewElements: serialConnectorPreviewElements,
      context: context,
    );
    return context;
  }

  void _paintSceneElement({
    required Canvas canvas,
    required ElementState element,
    required double scale,
    required _SceneRenderContext sceneContext,
  }) {
    elementRenderer.renderElement(
      canvas: canvas,
      element: element,
      scaleFactor: scale,
      registry: renderKey.elementRegistry,
      locale: renderKey.locale,
    );
    if (sceneContext.shouldPaintSerialConnectors) {
      drawSerialNumberConnectorsForText(
        canvas: canvas,
        textElement: element,
        connectorsByTextId: sceneContext.serialConnectors,
      );
    }
  }

  Map<String, ElementState> _extractSerialConnectorPreviewElements(
    Map<String, ElementState> previewElementsById,
  ) {
    if (previewElementsById.isEmpty) {
      return const <String, ElementState>{};
    }

    Map<String, ElementState>? relevant;
    for (final entry in previewElementsById.entries) {
      final preview = entry.value;
      final data = preview.data;
      if (data is SerialNumberData || data is TextData) {
        (relevant ??= <String, ElementState>{})[entry.key] = preview;
      }
    }
    return relevant ?? const <String, ElementState>{};
  }

  FilterRenderCacheContext _buildFilterCacheContext({required double scale}) {
    final localeTag = renderKey.locale?.toLanguageTag() ?? '';
    final normalizedScale = scale == 0 ? 1.0 : scale;
    return FilterRenderCacheContext(
      domain: FilterRenderCacheDomain.dynamicLayer,
      documentVersion: renderKey.documentVersion,
      textRenderingCacheRevision: renderKey.textRenderingCacheRevision,
      scaleKey: (normalizedScale * 1000).round(),
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
    final hasPreviewElements = dynamicPreviewIds.isNotEmpty;
    final hasCreatingFilter = creatingFilterId != null;
    final hasSerialConnectorTexts = serialConnectorTextIds.isNotEmpty;
    if (!hasPreviewElements && !hasCreatingFilter && !hasSerialConnectorTexts) {
      return const <String>{};
    }

    final dynamicElementIds = <String>{};
    if (hasPreviewElements) {
      dynamicElementIds.addAll(dynamicPreviewIds);
    }
    if (creatingFilterId != null) {
      dynamicElementIds.add(creatingFilterId);
    }
    if (hasSerialConnectorTexts) {
      dynamicElementIds.addAll(serialConnectorTextIds);
    }
    return dynamicElementIds;
  }

  Set<String> _resolveSelectedFilterDynamicIds({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
  }) {
    final selectedIds = renderKey.selectedIds;
    if (selectedIds.isEmpty) {
      return const <String>{};
    }

    Set<String>? selectedFilterIds;
    for (final selectedId in selectedIds) {
      final effective =
          previewElementsById[selectedId] ??
          document.getElementById(selectedId);
      if (effective == null || effective.data is! FilterData) {
        continue;
      }
      (selectedFilterIds ??= <String>{}).add(selectedId);
    }
    return selectedFilterIds == null
        ? const <String>{}
        : Set<String>.unmodifiable(selectedFilterIds);
  }

  Set<String> _mergeDynamicElementIds({
    required Set<String> baseDynamicIds,
    required Set<String> additionalDynamicIds,
  }) {
    if (additionalDynamicIds.isEmpty) {
      return baseDynamicIds;
    }
    if (baseDynamicIds.isEmpty) {
      return additionalDynamicIds;
    }
    return <String>{...baseDynamicIds, ...additionalDynamicIds};
  }

  Set<String> _resolveDynamicPreviewElementIds(
    Map<String, ElementState> previewElementsById,
  ) {
    if (previewElementsById.isEmpty) {
      return const <String>{};
    }

    final document = stateView.state.domain.document;
    final dynamicIds = <String>{};
    for (final entry in previewElementsById.entries) {
      final persisted = document.getElementById(entry.key);
      if (persisted == null || persisted != entry.value) {
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
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final handleTolerance =
        selectionConfig.interaction.handleTolerance / effectiveScale;
    final loopThreshold = handleTolerance * 1.5;
    final baseHandleSize =
        selectionConfig.render.controlPointSize / effectiveScale;
    // Apply multiplier for arrow point handles to make them larger
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
    final strokeWidth = selectionConfig.render.strokeWidth / effectiveScale;
    final fillColor = selectionConfig.render.cornerFillColor;
    final strokeColor = selectionConfig.render.strokeColor;
    final highlightStroke = strokeColor.withValues(alpha: 0.95);

    final hoveredHandle = renderKey.hoveredArrowHandle;
    final activeHandle = renderKey.activeArrowHandle;
    final shouldDelete = renderKey.arrowDeleteIndicatorVisible;
    final deletePosition = activeHandle == null || !shouldDelete
        ? null
        : _resolveHandlePosition(overlay, activeHandle);

    canvas.save();
    if (effectiveElement.rotation != 0) {
      canvas
        ..translate(
          effectiveElement.rect.centerX,
          effectiveElement.rect.centerY,
        )
        ..rotate(effectiveElement.rotation)
        ..translate(
          -effectiveElement.rect.centerX,
          -effectiveElement.rect.centerY,
        );
    }
    canvas.translate(effectiveElement.rect.minX, effectiveElement.rect.minY);

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

    for (final handle in overlay.addablePoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
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
      final radius = addableRadius;
      canvas
        ..drawCircle(center, radius, fillPaint)
        ..drawCircle(center, radius, strokePaint);
    }

    for (final handle in overlay.turningPoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, paints.hoverOuterFill);
      }
      final fillPaint = paints.turningFill;
      final strokePaint = isHighlighted
          ? paints.turningStrokeHighlighted
          : paints.turningStroke;
      canvas
        ..drawCircle(center, turnRadius, fillPaint)
        ..drawCircle(center, turnRadius, strokePaint);
    }

    for (final handle in overlay.loopPoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, paints.hoverOuterFill);
      }
      final radius = handle.kind == ArrowPointKind.loopEnd
          ? loopOuterRadius
          : loopInnerRadius;

      // Inner loop point (loopStart) has filled style like bend points
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
      final center = _localOffset(effectiveElement.rect, deletePosition);
      canvas.drawCircle(center, turnRadius * 1.35, paints.deleteStroke);
    }

    canvas.restore();
  }

  void _drawArrowBindingHighlight({
    required Canvas canvas,
    required double scale,
  }) {
    final highlights = _resolveArrowBindingHighlights();
    if (highlights.isEmpty) {
      return;
    }
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final strokeColor = renderKey.selectionConfig.render.strokeColor;
    final paint = createBindingHighlightPaint(
      color: strokeColor,
      scale: effectiveScale,
    );

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

  void _drawArrowHoverOutline({
    required Canvas canvas,
    required ElementState element,
    required double scale,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      return;
    }

    final rect = element.rect;
    final cached = arrowVisualCache.resolve(element: element, data: data);
    if (cached.geometry.localPoints.length < 2) {
      return;
    }

    // Use selection stroke width for the hover outline.
    final hoverStrokeWidth = renderKey.hoverSelectionConfig.render.strokeWidth;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    // Use hover selection color with modified appearance
    final hoverColor = renderKey.hoverSelectionConfig.render.strokeColor;
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

  void _drawTextHoverUnderlines({
    required Canvas canvas,
    required ElementState element,
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
    final underlineColor = renderKey.hoverSelectionConfig.render.strokeColor;
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
    required double scale,
  }) {
    _drawFreeDrawOutline(
      canvas: canvas,
      element: element,
      scale: scale,
      color: renderKey.hoverSelectionConfig.render.strokeColor,
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
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final path = cached.path;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / effectiveScale
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

  DrawPoint? _resolveHandlePosition(
    ArrowPointOverlay overlay,
    ArrowPointHandle handle,
  ) {
    for (final candidate in overlay.turningPoints) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    for (final candidate in overlay.addablePoints) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    for (final candidate in overlay.loopPoints) {
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
      if (element == null || element.data is! ArrowLikeData) {
        return _dedupeArrowBindingHighlights(highlights);
      }
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
      return _dedupeArrowBindingHighlights(highlights);
    }
    if (interaction is CreatingState) {
      final element = interaction.element;
      final data = element.data;
      if (data is! ArrowLikeData || !interaction.isPointCreation) {
        return _dedupeArrowBindingHighlights(highlights);
      }
      final endHighlight = _highlightFromBinding(data.endBinding);
      if (endHighlight != null) {
        highlights.add(endHighlight);
      }
      final startHighlight = _highlightFromBinding(data.startBinding);
      if (startHighlight != null) {
        highlights.add(startHighlight);
      }
      return _dedupeArrowBindingHighlights(highlights);
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
  void _drawBoxSelection(Canvas canvas, DrawRect bounds, double scale) {
    final boxSelectionConfig = renderKey.boxSelectionConfig;

    // Draw translucent fill.
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = boxSelectionConfig.fillColor.withValues(
        alpha: boxSelectionConfig.fillOpacity,
      );

    // Draw stroke.
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          boxSelectionConfig.strokeWidth / (scale == 0 ? 1.0 : scale)
      ..color = boxSelectionConfig.strokeColor
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
    required double scale,
  }) {
    final config = renderKey.snapConfig;
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final invScale = 1.0 / effectiveScale;
    final strokeWidth = config.lineWidth * invScale;
    final markerSize = config.markerSize * invScale;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = config.lineColor
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
          scale: effectiveScale,
          color: config.lineColor,
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
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final textPainter = _gapLabelPainter
      ..text = TextSpan(
        text: label.toStringAsFixed(0),
        style: TextStyle(color: color, fontSize: 10 / effectiveScale),
      )
      ..layout();

    final mid = DrawPoint(
      x: (guide.start.x + guide.end.x) / 2,
      y: (guide.start.y + guide.end.y) / 2,
    );
    final offset = Offset(
      mid.x - textPainter.width / 2,
      mid.y - textPainter.height - (4 / effectiveScale),
    );
    textPainter.paint(canvas, offset);
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
      color: renderKey.selectionConfig.render.strokeColor,
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

class _SceneRenderContext {
  const _SceneRenderContext({
    required this.hasFilterElement,
    required this.hasDynamicFilterElement,
    required this.shouldPaintSerialConnectors,
    required this.serialConnectors,
    required this.dynamicElementIds,
  });

  final bool hasFilterElement;
  final bool hasDynamicFilterElement;
  final bool shouldPaintSerialConnectors;
  final Map<String, List<SerialNumberTextConnector>> serialConnectors;
  final Set<String> dynamicElementIds;
}

class _SceneRenderContextCacheEntry {
  _SceneRenderContextCacheEntry({
    required this.document,
    required this.elements,
    required Set<String> dynamicPreviewIds,
    required this.creatingFilterId,
    required Set<String> selectedFilterIds,
    required Map<String, ElementState> serialConnectorPreviewElements,
    required this.context,
  }) : dynamicPreviewIds = Set<String>.unmodifiable(dynamicPreviewIds),
       selectedFilterIds = Set<String>.unmodifiable(selectedFilterIds),
       serialConnectorPreviewElements = Map<String, ElementState>.unmodifiable(
         serialConnectorPreviewElements,
       );

  final DocumentState document;
  final List<ElementState> elements;
  final Set<String> dynamicPreviewIds;
  final String? creatingFilterId;
  final Set<String> selectedFilterIds;
  final Map<String, ElementState> serialConnectorPreviewElements;
  final _SceneRenderContext context;

  bool matches({
    required DocumentState document,
    required List<ElementState> elements,
    required Set<String> dynamicPreviewIds,
    required String? creatingFilterId,
    required Set<String> selectedFilterIds,
    required Map<String, ElementState> serialConnectorPreviewElements,
  }) =>
      identical(this.document, document) &&
      identical(this.elements, elements) &&
      this.creatingFilterId == creatingFilterId &&
      _setEquals(this.dynamicPreviewIds, dynamicPreviewIds) &&
      _setEquals(this.selectedFilterIds, selectedFilterIds) &&
      _mapsEqual(
        this.serialConnectorPreviewElements,
        serialConnectorPreviewElements,
      );

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }

  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }
}
