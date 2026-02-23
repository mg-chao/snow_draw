import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'package:snow_draw_core/snow_draw_core.dart';

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

/// Render key for the single scene canvas.
///
/// [framePlan] is the authoritative paint input for the single-canvas path.
///
/// The remaining fields are retained for repaint-key stability and
/// backend-only render concerns (for example filter cache context and
/// interaction diagnostics) that are not encoded directly in core tasks.
@immutable
class SceneCanvasRenderKey {
  const SceneCanvasRenderKey({
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
    required this.scaleFactor,
    required this.selectionConfig,
    required this.boxSelectionConfig,
    required this.snapConfig,
    required this.isHighlightMaskVisible,
    required this.highlightMaskConfig,
    required this.isWatermarkVisible,
    required this.watermarkConfig,
    required this.canvasConfig,
    required this.gridConfig,
    required this.elementRegistry,
    required this.performanceMonitoringEnabled,
    required this.framePlan,
    this.textMetricsService = defaultTextMetricsService,
    this.preferFastFilterFallback = false,
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
  /// canvas overlays repaint with updated glyph shaping.
  final int textRenderingCacheRevision;

  /// Camera state for viewport.
  final CameraState camera;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

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

  /// Whether highlight-mask overlay pixels should be painted.
  final bool isHighlightMaskVisible;

  /// Highlight mask configuration.
  final HighlightMaskConfig highlightMaskConfig;

  /// Whether watermark overlay pixels should be painted.
  final bool isWatermarkVisible;

  /// Watermark configuration.
  final WatermarkConfig watermarkConfig;

  /// Canvas configuration.
  final CanvasConfig canvasConfig;

  /// Grid configuration.
  final GridConfig gridConfig;

  /// Element registry for rendering.
  final ElementRegistry elementRegistry;

  /// Text metrics service used while encoding text-based scenes.
  final TextMetricsService textMetricsService;

  /// Whether runtime render diagnostics logging is enabled.
  final bool performanceMonitoringEnabled;

  /// Locale used for text layout/rendering.
  final Locale? locale;

  /// Core-generated frame render plan snapshot for this key.
  final FrameRenderPlan framePlan;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneCanvasRenderKey &&
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
          mapEquals(other.previewElementsById, previewElementsById) &&
          other.preferFastFilterFallback == preferFastFilterFallback &&
          other.scaleFactor == scaleFactor &&
          other.selectionConfig == selectionConfig &&
          other.boxSelectionConfig == boxSelectionConfig &&
          other.snapConfig == snapConfig &&
          other.isHighlightMaskVisible == isHighlightMaskVisible &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.isWatermarkVisible == isWatermarkVisible &&
          other.watermarkConfig == watermarkConfig &&
          other.canvasConfig == canvasConfig &&
          other.gridConfig == gridConfig &&
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
    _mapHash(previewElementsById),
    preferFastFilterFallback,
    scaleFactor,
    selectionConfig,
    boxSelectionConfig,
    snapConfig,
    isHighlightMaskVisible,
    highlightMaskConfig,
    isWatermarkVisible,
    watermarkConfig,
    canvasConfig,
    gridConfig,
    elementRegistry,
    identityHashCode(textMetricsService),
    performanceMonitoringEnabled,
    locale,
  ]);
}
