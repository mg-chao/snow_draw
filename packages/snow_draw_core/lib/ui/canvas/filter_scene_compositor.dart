import 'dart:ui';

import '../../draw/models/element_state.dart';
import 'filter_pipeline/filter_render_diagnostics.dart';
import 'filter_pipeline/filter_segment_renderer.dart';

typedef SceneElementPainter =
    void Function(Canvas canvas, ElementState element);

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
  }) {
    _renderer.paint(
      canvas: canvas,
      elements: elements,
      paintElement: paintElement,
    );
  }

  /// Clears internal caches held by the renderer.
  void clearCaches() {
    _renderer.clearCaches();
  }
}

final filterSceneCompositor = FilterSceneCompositor();
