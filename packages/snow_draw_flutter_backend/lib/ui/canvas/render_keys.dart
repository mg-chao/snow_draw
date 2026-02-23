import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'highlight_mask_visibility.dart';
import 'watermark_visibility.dart';

int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered(
  map.entries.map((entry) => Object.hash(entry.key, entry.value)),
);

/// Snapshot of element creation state for render key comparison.
@immutable
class CreatingElementSnapshot {
  const CreatingElementSnapshot({
    required this.element,
    required this.currentRect,
    this.creationRevision = 0,
  });

  /// The element being created.
  final ElementState element;

  /// Current rect of the element being created.
  final DrawRect currentRect;

  /// Monotonic revision for in-progress creation previews.
  ///
  /// Used by high-frequency tools (such as free draw) whose visual preview can
  /// change without changing [element] or [currentRect].
  final int creationRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreatingElementSnapshot &&
          other.element == element &&
          other.currentRect == currentRect &&
          other.creationRevision == creationRevision;

  @override
  int get hashCode => Object.hash(element, currentRect, creationRevision);
}

/// Render key for static canvas.
///
/// Captures exactly what affects the static canvas rendering:
/// - Document elements (via version)
/// - Camera state (position, zoom)
/// - Preview elements (during editing)
/// - Dynamic layer split index
/// - Canvas/grid config, scale factor, element registry
@immutable
class StaticCanvasRenderKey {
  const StaticCanvasRenderKey({
    required this.documentVersion,
    required this.textRenderingCacheRevision,
    required this.camera,
    required this.previewElementsById,
    required this.dynamicLayerStartIndex,
    required this.skipBaseElementScene,
    required this.scaleFactor,
    required this.canvasConfig,
    required this.gridConfig,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.watermarkLayer,
    required this.watermarkConfig,
    required this.elementRegistry,
    required this.performanceMonitoringEnabled,
    this.textMetricsService = defaultTextMetricsService,
    this.locale,
  });

  /// Document version for detecting element changes.
  final int documentVersion;

  /// Revision for text rendering cache invalidation.
  ///
  /// Incremented when runtime font loading clears paragraph/layout caches so
  /// canvas painters can rebuild text paragraphs with the newly available
  /// glyphs.
  final int textRenderingCacheRevision;

  /// Camera state for viewport.
  final CameraState camera;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

  /// First element index that renders on the dynamic layer.
  final int? dynamicLayerStartIndex;

  /// Whether static painter should skip base element scene rendering.
  final bool skipBaseElementScene;

  /// Canvas scale factor.
  final double scaleFactor;

  /// Canvas configuration.
  final CanvasConfig canvasConfig;

  /// Grid configuration.
  final GridConfig gridConfig;

  /// Highlight mask rendering layer.
  final HighlightMaskLayer highlightMaskLayer;

  /// Highlight mask configuration.
  final HighlightMaskConfig highlightMaskConfig;

  /// Watermark rendering layer.
  final WatermarkLayer watermarkLayer;

  /// Watermark configuration.
  final WatermarkConfig watermarkConfig;

  /// Element registry for rendering.
  final ElementRegistry elementRegistry;

  /// Text metrics service used while encoding text-based scenes.
  final TextMetricsService textMetricsService;

  /// Whether runtime render diagnostics logging is enabled.
  final bool performanceMonitoringEnabled;

  /// Locale used for text layout/rendering.
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaticCanvasRenderKey &&
          other.documentVersion == documentVersion &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          other.camera == camera &&
          mapEquals(other.previewElementsById, previewElementsById) &&
          other.dynamicLayerStartIndex == dynamicLayerStartIndex &&
          other.skipBaseElementScene == skipBaseElementScene &&
          other.scaleFactor == scaleFactor &&
          other.canvasConfig == canvasConfig &&
          other.gridConfig == gridConfig &&
          other.highlightMaskLayer == highlightMaskLayer &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.watermarkLayer == watermarkLayer &&
          other.watermarkConfig == watermarkConfig &&
          other.elementRegistry == elementRegistry &&
          identical(other.textMetricsService, textMetricsService) &&
          other.performanceMonitoringEnabled == performanceMonitoringEnabled &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    documentVersion,
    textRenderingCacheRevision,
    camera,
    _mapHash(previewElementsById),
    dynamicLayerStartIndex,
    skipBaseElementScene,
    scaleFactor,
    canvasConfig,
    gridConfig,
    highlightMaskLayer,
    highlightMaskConfig,
    watermarkLayer,
    watermarkConfig,
    elementRegistry,
    identityHashCode(textMetricsService),
    performanceMonitoringEnabled,
    locale,
  );
}

/// Render key for dynamic canvas.
///
/// Captures exactly what affects the dynamic canvas rendering:
/// - Creating element state
/// - Effective selection (bounds, center, rotation)
/// - Box selection bounds
/// - Selected/hovered element IDs (for selection outlines)
/// - Arrow handle interaction state (including delete indicator visibility)
/// - Document version (for selection outline refresh)
/// - Preview elements and dynamic layer split index
/// - Camera state (position/zoom), selection/box selection config, scale factor
@immutable
class DynamicCanvasRenderKey {
  const DynamicCanvasRenderKey({
    required this.creatingElement,
    required this.effectiveSelection,
    required this.boxSelectionBounds,
    required this.selectedIds,
    required this.hoveredElementId,
    required this.hoveredBindingElementId,
    required this.hoveredArrowHandle,
    required this.activeArrowHandle,
    required this.arrowDeleteIndicatorVisible,
    required this.hoverSelectionConfig,
    required this.snapGuides,
    required this.documentVersion,
    required this.textRenderingCacheRevision,
    required this.camera,
    required this.previewElementsById,
    required this.optimizedDynamicElementIds,
    required this.optimizedSceneHasPotentialOccluders,
    required this.dynamicLayerStartIndex,
    required this.rendersWholeElementScene,
    required this.scaleFactor,
    required this.selectionConfig,
    required this.boxSelectionConfig,
    required this.snapConfig,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.watermarkLayer,
    required this.watermarkConfig,
    required this.elementRegistry,
    required this.performanceMonitoringEnabled,
    this.textMetricsService = defaultTextMetricsService,
    this.preferFastFilterFallback = false,
    this.previewElementsRevision,
    this.dynamicPreviewElementIds,
    this.locale,
  });

  /// Snapshot of element being created, or null if not creating.
  final CreatingElementSnapshot? creatingElement;

  /// Effective selection state.
  final EffectiveSelection effectiveSelection;

  /// Box selection bounds, or null if not box selecting.
  final DrawRect? boxSelectionBounds;

  /// Selected element IDs for rendering outlines.
  final Set<String> selectedIds;

  /// Hovered element ID for selection preview outline.
  final String? hoveredElementId;
  final String? hoveredBindingElementId;
  final ArrowPointHandle? hoveredArrowHandle;
  final ArrowPointHandle? activeArrowHandle;

  /// Whether the arrow-point delete indicator should be painted.
  final bool arrowDeleteIndicatorVisible;

  /// Selection config for hover outlines.
  final SelectionConfig hoverSelectionConfig;

  /// Snap guide overlays.
  final List<SnapGuide> snapGuides;

  /// Document version for detecting element geometry changes.
  final int documentVersion;

  /// Revision for text rendering cache invalidation.
  ///
  /// Incremented when runtime font loading clears paragraph/layout caches so
  /// dynamic overlays repaint with updated glyph shaping.
  final int textRenderingCacheRevision;

  /// Camera state for viewport.
  final CameraState camera;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

  /// Optional monotonically increasing preview-map revision.
  ///
  /// When provided, equality and hashing use `[previewElementsById]` identity
  /// plus this revision instead of deep map comparisons.
  final int? previewElementsRevision;

  /// Optional dynamic-preview override used by interaction scene caching.
  ///
  /// When set, dynamic-layer caching treats only these preview ids as volatile.
  /// This is a performance hint and does not change final visual output.
  final Set<String>? dynamicPreviewElementIds;

  /// Element ids for localized dynamic-scene optimization.
  ///
  /// When non-empty, the dynamic painter renders only these optimized
  /// elements and overlapping top-order occluders instead of every element
  /// above the selection.
  final Set<String> optimizedDynamicElementIds;

  /// Whether optimized-scene rendering has any non-optimized element above
  /// the optimized seed range.
  ///
  /// When `false`, dynamic painters can skip expensive occluder-resolution
  /// queries and render optimized elements directly in z-order.
  final bool optimizedSceneHasPotentialOccluders;

  /// First element index that renders on the dynamic layer.
  final int? dynamicLayerStartIndex;

  /// Whether dynamic painter renders the whole element scene.
  final bool rendersWholeElementScene;

  /// Whether filter rendering should prioritize responsiveness this frame.
  ///
  /// This hint is used for high-frequency filter style drags where full
  /// fidelity often falls back to CPU rendering and hurts input latency.
  final bool preferFastFilterFallback;

  /// Canvas scale factor.
  final double scaleFactor;

  /// Selection configuration.
  final SelectionConfig selectionConfig;

  /// Box selection configuration.
  final BoxSelectionConfig boxSelectionConfig;

  /// Snap configuration.
  final SnapConfig snapConfig;

  /// Highlight mask rendering layer.
  final HighlightMaskLayer highlightMaskLayer;

  /// Highlight mask configuration.
  final HighlightMaskConfig highlightMaskConfig;

  /// Watermark rendering layer.
  final WatermarkLayer watermarkLayer;

  /// Watermark configuration.
  final WatermarkConfig watermarkConfig;

  /// Element registry for rendering.
  final ElementRegistry elementRegistry;

  /// Text metrics service used while encoding text-based scenes.
  final TextMetricsService textMetricsService;

  /// Whether runtime render diagnostics logging is enabled.
  final bool performanceMonitoringEnabled;

  /// Locale used for text layout/rendering.
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicCanvasRenderKey &&
          other.creatingElement == creatingElement &&
          other.effectiveSelection == effectiveSelection &&
          other.boxSelectionBounds == boxSelectionBounds &&
          setEquals(other.selectedIds, selectedIds) &&
          other.hoveredElementId == hoveredElementId &&
          other.hoveredBindingElementId == hoveredBindingElementId &&
          other.hoveredArrowHandle == hoveredArrowHandle &&
          other.activeArrowHandle == activeArrowHandle &&
          other.arrowDeleteIndicatorVisible == arrowDeleteIndicatorVisible &&
          other.hoverSelectionConfig == hoverSelectionConfig &&
          listEquals(other.snapGuides, snapGuides) &&
          other.documentVersion == documentVersion &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          other.camera == camera &&
          _previewMapsEqual(other) &&
          setEquals(
            other.optimizedDynamicElementIds,
            optimizedDynamicElementIds,
          ) &&
          other.optimizedSceneHasPotentialOccluders ==
              optimizedSceneHasPotentialOccluders &&
          other.dynamicLayerStartIndex == dynamicLayerStartIndex &&
          other.rendersWholeElementScene == rendersWholeElementScene &&
          other.preferFastFilterFallback == preferFastFilterFallback &&
          other.scaleFactor == scaleFactor &&
          other.selectionConfig == selectionConfig &&
          other.boxSelectionConfig == boxSelectionConfig &&
          other.snapConfig == snapConfig &&
          other.highlightMaskLayer == highlightMaskLayer &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.watermarkLayer == watermarkLayer &&
          other.watermarkConfig == watermarkConfig &&
          other.elementRegistry == elementRegistry &&
          identical(other.textMetricsService, textMetricsService) &&
          other.performanceMonitoringEnabled == performanceMonitoringEnabled &&
          other.locale == locale;

  @override
  int get hashCode => Object.hashAll([
    creatingElement,
    effectiveSelection,
    boxSelectionBounds,
    Object.hashAllUnordered(selectedIds),
    hoveredElementId,
    hoveredBindingElementId,
    hoveredArrowHandle,
    activeArrowHandle,
    arrowDeleteIndicatorVisible,
    hoverSelectionConfig,
    Object.hashAll(snapGuides),
    documentVersion,
    textRenderingCacheRevision,
    camera,
    _previewMapHash(),
    Object.hashAllUnordered(optimizedDynamicElementIds),
    optimizedSceneHasPotentialOccluders,
    dynamicLayerStartIndex,
    rendersWholeElementScene,
    preferFastFilterFallback,
    scaleFactor,
    selectionConfig,
    boxSelectionConfig,
    snapConfig,
    highlightMaskLayer,
    highlightMaskConfig,
    watermarkLayer,
    watermarkConfig,
    elementRegistry,
    identityHashCode(textMetricsService),
    performanceMonitoringEnabled,
    locale,
  ]);

  bool _previewMapsEqual(DynamicCanvasRenderKey other) {
    if (previewElementsRevision != other.previewElementsRevision) {
      return false;
    }
    if (previewElementsRevision != null) {
      return identical(other.previewElementsById, previewElementsById);
    }
    return mapEquals(other.previewElementsById, previewElementsById);
  }

  int _previewMapHash() {
    final revision = previewElementsRevision;
    if (revision != null) {
      return Object.hash(identityHashCode(previewElementsById), revision);
    }
    return _mapHash(previewElementsById);
  }
}
