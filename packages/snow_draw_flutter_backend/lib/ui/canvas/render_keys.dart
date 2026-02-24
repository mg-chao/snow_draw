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
/// [framePlan] is the authoritative source for non-element paint tasks in the
/// single-canvas path (background, overlays, guides, etc.).
///
/// Element scene pixels are resolved from [DrawStateView] and preview snapshots
/// in the backend painter, so backend-only fields remain part of this key.
@immutable
class SceneCanvasRenderKey {
  SceneCanvasRenderKey({
    required this.creatingElement,
    required this.sceneContentFingerprint,
    required this.textRenderingCacheRevision,
    required Map<String, ElementState> previewElementsById,
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

  /// Fingerprint of scene inputs that can affect element-layer pixels.
  ///
  /// This is intentionally finer-grained than document-wide revisions so
  /// offscreen mutations that cannot affect the current frame do not trigger
  /// unnecessary canvas repaints.
  final int sceneContentFingerprint;

  /// Revision for text rendering cache invalidation.
  ///
  /// Incremented when runtime font loading clears paragraph/layout caches so
  /// scene-dependent caches repaint with updated glyph shaping.
  final int textRenderingCacheRevision;

  /// Preview elements during editing.
  final Map<String, ElementState> previewElementsById;

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
          other.sceneContentFingerprint == sceneContentFingerprint &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          mapEquals(other.previewElementsById, previewElementsById) &&
          other.elementRegistry == elementRegistry &&
          identical(other.textMetricsService, textMetricsService) &&
          other.performanceMonitoringEnabled == performanceMonitoringEnabled &&
          other.locale == locale &&
          other.framePlan == framePlan;

  @override
  int get hashCode => Object.hashAll([
    creatingElement,
    sceneContentFingerprint,
    textRenderingCacheRevision,
    _mapHash(previewElementsById),
    elementRegistry,
    identityHashCode(textMetricsService),
    performanceMonitoringEnabled,
    locale,
    framePlan,
  ]);
}
