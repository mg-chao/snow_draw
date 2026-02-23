import 'package:meta/meta.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'highlight_mask_visibility.dart';
import 'render_keys.dart';
import 'watermark_visibility.dart';

/// Resolves preview elements for the unified canvas scene.
typedef DynamicPreviewResolver =
    Map<String, ElementState> Function(DrawStateView view);

/// Resolves dynamic preview elements for a localized optimized scene.
typedef DynamicPreviewByOptimizedIdsResolver =
    Map<String, ElementState> Function(
      DrawStateView view,
      Set<String> optimizedElementIds,
    );

/// Resolves the subset of preview ids that should be treated as dynamic.
typedef DynamicPreviewElementIdsResolver =
    Set<String> Function(
      DrawStateView view,
      Map<String, ElementState> previewElementsById,
    );

/// Cached dynamic-scene payload derived from a previous dynamic render key.
///
/// Interaction-only updates (for example rectangle drag updates) often mutate
/// only preview geometry while document topology remains stable. In those
/// cases we can reuse optimization and overlay routing metadata from the
/// previous render key and rebuild only the preview subset for the new state.
@immutable
class InteractionDynamicSceneSnapshot {
  InteractionDynamicSceneSnapshot({
    required Map<String, ElementState> previewElementsById,
    required Set<String> dynamicPreviewElementIds,
    required Set<String> optimizedDynamicElementIds,
    required this.optimizedSceneHasPotentialOccluders,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.watermarkLayer,
    required this.watermarkConfig,
  }) : previewElementsById = Map<String, ElementState>.unmodifiable(
         previewElementsById,
       ),
       dynamicPreviewElementIds = Set<String>.unmodifiable(
         dynamicPreviewElementIds,
       ),
       optimizedDynamicElementIds = Set<String>.unmodifiable(
         optimizedDynamicElementIds,
       );

  final Map<String, ElementState> previewElementsById;
  final Set<String> dynamicPreviewElementIds;
  final Set<String> optimizedDynamicElementIds;
  final bool optimizedSceneHasPotentialOccluders;
  final HighlightMaskLayer highlightMaskLayer;
  final HighlightMaskConfig highlightMaskConfig;
  final WatermarkLayer watermarkLayer;
  final WatermarkConfig watermarkConfig;
}

/// Resolves the dynamic-scene payload for interaction-only updates by reusing
/// metadata from [previousRenderKey].
///
/// This avoids recomputing dynamic-scene optimization plans and highlight-mask
/// routing for every pointer frame while still rebuilding preview elements for
/// the latest state.
InteractionDynamicSceneSnapshot resolveInteractionDynamicSceneFromCachedKey({
  required DrawStateView stateView,
  required DynamicCanvasRenderKey previousRenderKey,
  required DynamicPreviewResolver resolvePreviewElements,
  required DynamicPreviewByOptimizedIdsResolver resolvePreviewByOptimizedIds,
  required DynamicPreviewElementIdsResolver resolveDynamicPreviewElementIds,
}) {
  final optimizedDynamicElementIds =
      previousRenderKey.optimizedDynamicElementIds;
  final hasOptimizedDynamicElements = optimizedDynamicElementIds.isNotEmpty;
  final previewElementsById = hasOptimizedDynamicElements
      ? resolvePreviewByOptimizedIds(stateView, optimizedDynamicElementIds)
      : resolvePreviewElements(stateView);
  return InteractionDynamicSceneSnapshot(
    previewElementsById: previewElementsById,
    dynamicPreviewElementIds: resolveDynamicPreviewElementIds(
      stateView,
      previewElementsById,
    ),
    optimizedDynamicElementIds: optimizedDynamicElementIds,
    optimizedSceneHasPotentialOccluders:
        hasOptimizedDynamicElements &&
        previousRenderKey.optimizedSceneHasPotentialOccluders,
    highlightMaskLayer: previousRenderKey.highlightMaskLayer,
    highlightMaskConfig: previousRenderKey.highlightMaskConfig,
    watermarkLayer: previousRenderKey.watermarkLayer,
    watermarkConfig: previousRenderKey.watermarkConfig,
  );
}
