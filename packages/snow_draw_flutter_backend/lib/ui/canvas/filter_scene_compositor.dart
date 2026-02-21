import 'dart:ui';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'filter_pipeline/filter_render_diagnostics.dart';
import 'filter_pipeline/filter_segment_renderer.dart';
export 'filter_pipeline/filter_segment_renderer.dart'
    show
        FilterRenderCacheContext,
        FilterRenderCacheDomain,
        FilterRenderHints,
        SceneElementPainter;

/// Backward-compatible facade over the segmented filter pipeline.
///
/// This adapter preserves existing call sites while delegating to the new
/// renderer implementation.
class FilterSceneCompositor {
  FilterSceneCompositor({FilterSegmentRenderer? renderer})
    : _renderer = renderer ?? FilterSegmentRenderer();

  final FilterSegmentRenderer _renderer;

  /// Latest completed frame diagnostics.
  FilterRenderDiagnostics get lastDiagnostics => _renderer.lastDiagnostics;

  /// Paint elements with filter-aware compositing.
  void paintElements({
    required Canvas canvas,
    required List<ElementState> elements,
    required SceneElementPainter paintElement,
    FilterRenderCacheContext? cacheContext,
    Rect? visibleBounds,
    Set<String> dynamicElementIds = const <String>{},
    FilterRenderHints renderHints = const FilterRenderHints(),
  }) {
    _renderer.paint(
      canvas: canvas,
      elements: elements,
      paintElement: paintElement,
      cacheContext: cacheContext,
      visibleBounds: visibleBounds,
      dynamicElementIds: dynamicElementIds,
      renderHints: renderHints,
    );
  }

  /// Clears internal caches held by the renderer.
  void clearCaches() => _renderer.clearCaches();
}

final filterSceneCompositor = FilterSceneCompositor();
