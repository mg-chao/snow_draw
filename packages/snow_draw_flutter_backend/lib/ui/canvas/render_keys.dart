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
/// Remaining fields cover backend-only concerns that are not encoded directly
/// into core render tasks.
@immutable
class SceneCanvasRenderKey {
  SceneCanvasRenderKey({
    required this.creatingElement,
    required this.hoveredBindingElementId,
    required this.hoveredArrowHandle,
    required this.selectionConfig,
    required this.documentVersion,
    required this.textRenderingCacheRevision,
    required Map<String, ElementState> previewElementsById,
    required this.preferFastFilterFallback,
    required this.elementRegistry,
    required this.performanceMonitoringEnabled,
    required this.framePlan,
    this.textMetricsService = defaultTextMetricsService,
    this.locale,
  }) : previewElementsById = previewElementsById.isEmpty
           ? const <String, ElementState>{}
           : Map<String, ElementState>.unmodifiable(previewElementsById);

  /// Snapshot of element being created, or null if not creating.
  final CreatingElementSnapshot? creatingElement;

  /// Hover binding information for arrow-binding highlights.
  final String? hoveredBindingElementId;
  final ArrowPointHandle? hoveredArrowHandle;

  /// Selection config used by backend-only overlay rendering.
  final SelectionConfig selectionConfig;

  /// Document version for detecting element geometry changes.
  final int documentVersion;

  /// Revision for text rendering cache invalidation.
  ///
  /// Incremented when runtime font loading clears paragraph/layout caches so
  /// canvas overlays repaint with updated glyph shaping.
  final int textRenderingCacheRevision;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

  /// Whether filter rendering should prioritize responsiveness this frame.
  ///
  /// This hint is used for high-frequency filter style drags where full
  /// fidelity often falls back to CPU rendering and hurts input latency.
  final bool preferFastFilterFallback;

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
          other.hoveredBindingElementId == hoveredBindingElementId &&
          other.hoveredArrowHandle == hoveredArrowHandle &&
          other.selectionConfig == selectionConfig &&
          other.documentVersion == documentVersion &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          mapEquals(other.previewElementsById, previewElementsById) &&
          other.preferFastFilterFallback == preferFastFilterFallback &&
          other.elementRegistry == elementRegistry &&
          identical(other.textMetricsService, textMetricsService) &&
          other.performanceMonitoringEnabled == performanceMonitoringEnabled &&
          other.locale == locale &&
          other.framePlan == framePlan;

  @override
  int get hashCode => Object.hashAll([
    creatingElement,
    hoveredBindingElementId,
    hoveredArrowHandle,
    selectionConfig,
    documentVersion,
    textRenderingCacheRevision,
    _mapHash(previewElementsById),
    preferFastFilterFallback,
    elementRegistry,
    identityHashCode(textMetricsService),
    performanceMonitoringEnabled,
    locale,
    framePlan,
  ]);
}
