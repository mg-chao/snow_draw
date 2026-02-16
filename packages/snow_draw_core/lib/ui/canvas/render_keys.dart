import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/elements/core/element_registry_interface.dart';
import '../../draw/elements/types/arrow/arrow_points.dart';
import '../../draw/models/camera_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/snap_guides.dart';
import 'highlight_mask_visibility.dart';
import 'watermark_visibility.dart';

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
          _mapsEqual(other.previewElementsById, previewElementsById) &&
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
    performanceMonitoringEnabled,
    locale,
  );

  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
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

  static int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered(
    map.entries.map((entry) => Object.hash(entry.key, entry.value)),
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

  /// First element index that renders on the dynamic layer.
  final int? dynamicLayerStartIndex;

  /// Whether dynamic painter renders the whole element scene.
  final bool rendersWholeElementScene;

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
          _setEquals(other.selectedIds, selectedIds) &&
          other.hoveredElementId == hoveredElementId &&
          other.hoveredBindingElementId == hoveredBindingElementId &&
          other.hoveredArrowHandle == hoveredArrowHandle &&
          other.activeArrowHandle == activeArrowHandle &&
          other.arrowDeleteIndicatorVisible == arrowDeleteIndicatorVisible &&
          other.hoverSelectionConfig == hoverSelectionConfig &&
          _listEquals(other.snapGuides, snapGuides) &&
          other.documentVersion == documentVersion &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          other.camera == camera &&
          _mapsEqual(other.previewElementsById, previewElementsById) &&
          other.dynamicLayerStartIndex == dynamicLayerStartIndex &&
          other.rendersWholeElementScene == rendersWholeElementScene &&
          other.scaleFactor == scaleFactor &&
          other.selectionConfig == selectionConfig &&
          other.boxSelectionConfig == boxSelectionConfig &&
          other.snapConfig == snapConfig &&
          other.highlightMaskLayer == highlightMaskLayer &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.watermarkLayer == watermarkLayer &&
          other.watermarkConfig == watermarkConfig &&
          other.elementRegistry == elementRegistry &&
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
    dynamicLayerStartIndex,
    rendersWholeElementScene,
    scaleFactor,
    selectionConfig,
    boxSelectionConfig,
    snapConfig,
    highlightMaskLayer,
    highlightMaskConfig,
    watermarkLayer,
    watermarkConfig,
    elementRegistry,
    performanceMonitoringEnabled,
    locale,
  ]);

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final item in a) {
      if (!b.contains(item)) {
        return false;
      }
    }
    return true;
  }

  static bool _listEquals(List<SnapGuide> a, List<SnapGuide> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
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

  static int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered(
    map.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}
