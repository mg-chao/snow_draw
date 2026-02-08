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

/// Snapshot of element creation state for render key comparison.
@immutable
class CreatingElementSnapshot {
  const CreatingElementSnapshot({
    required this.element,
    required this.currentRect,
  });

  /// The element being created.
  final ElementState element;

  /// Current rect of the element being created.
  final DrawRect currentRect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreatingElementSnapshot &&
          other.element == element &&
          other.currentRect == currentRect;

  @override
  int get hashCode => Object.hash(element, currentRect);
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
    required this.camera,
    required this.previewElementsById,
    required this.dynamicLayerStartIndex,
    required this.scaleFactor,
    required this.canvasConfig,
    required this.gridConfig,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.elementRegistry,
    this.locale,
  });

  /// Document version for detecting element changes.
  final int documentVersion;

  /// Camera state for viewport.
  final CameraState camera;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

  /// First element index that renders on the dynamic layer.
  final int? dynamicLayerStartIndex;

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

  /// Element registry for rendering.
  final ElementRegistry elementRegistry;

  /// Locale used for text layout/rendering.
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaticCanvasRenderKey &&
          other.documentVersion == documentVersion &&
          other.camera == camera &&
          _mapsEqual(other.previewElementsById, previewElementsById) &&
          other.dynamicLayerStartIndex == dynamicLayerStartIndex &&
          other.scaleFactor == scaleFactor &&
          other.canvasConfig == canvasConfig &&
          other.gridConfig == gridConfig &&
          other.highlightMaskLayer == highlightMaskLayer &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.elementRegistry == elementRegistry &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    documentVersion,
    camera,
    Object.hashAll(
      previewElementsById.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    dynamicLayerStartIndex,
    scaleFactor,
    canvasConfig,
    gridConfig,
    highlightMaskLayer,
    highlightMaskConfig,
    elementRegistry,
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
}

/// Render key for dynamic canvas.
///
/// Captures exactly what affects the dynamic canvas rendering:
/// - Creating element state
/// - Effective selection (bounds, center, rotation)
/// - Box selection bounds
/// - Selected/hovered element IDs (for selection outlines)
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
    required this.hoverSelectionConfig,
    required this.snapGuides,
    required this.documentVersion,
    required this.camera,
    required this.previewElementsById,
    required this.dynamicLayerStartIndex,
    required this.scaleFactor,
    required this.selectionConfig,
    required this.boxSelectionConfig,
    required this.snapConfig,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.elementRegistry,
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

  /// Selection config for hover outlines.
  final SelectionConfig hoverSelectionConfig;

  /// Snap guide overlays.
  final List<SnapGuide> snapGuides;

  /// Document version for detecting element geometry changes.
  final int documentVersion;

  /// Camera state for viewport.
  final CameraState camera;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

  /// First element index that renders on the dynamic layer.
  final int? dynamicLayerStartIndex;

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

  /// Element registry for rendering.
  final ElementRegistry elementRegistry;

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
          other.hoverSelectionConfig == hoverSelectionConfig &&
          _listEquals(other.snapGuides, snapGuides) &&
          other.documentVersion == documentVersion &&
          other.camera == camera &&
          _mapsEqual(other.previewElementsById, previewElementsById) &&
          other.dynamicLayerStartIndex == dynamicLayerStartIndex &&
          other.scaleFactor == scaleFactor &&
          other.selectionConfig == selectionConfig &&
          other.boxSelectionConfig == boxSelectionConfig &&
          other.snapConfig == snapConfig &&
          other.highlightMaskLayer == highlightMaskLayer &&
          other.highlightMaskConfig == highlightMaskConfig &&
          other.elementRegistry == elementRegistry &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    creatingElement,
    effectiveSelection,
    boxSelectionBounds,
    Object.hashAllUnordered(selectedIds),
    hoveredElementId,
    hoveredBindingElementId,
    hoveredArrowHandle,
    activeArrowHandle,
    hoverSelectionConfig,
    Object.hashAll(snapGuides),
    documentVersion,
    camera,
    Object.hashAll(
      previewElementsById.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    dynamicLayerStartIndex,
    scaleFactor,
    selectionConfig,
    boxSelectionConfig,
    snapConfig,
    highlightMaskLayer,
    highlightMaskConfig,
    elementRegistry,
    locale,
  );

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
}
