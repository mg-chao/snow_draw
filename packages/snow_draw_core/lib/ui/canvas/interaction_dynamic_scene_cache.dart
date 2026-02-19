import 'package:meta/meta.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import 'highlight_mask_visibility.dart';
import 'render_keys.dart';
import 'watermark_visibility.dart';

/// Resolves dynamic preview elements based on a cached dynamic-layer split.
typedef DynamicPreviewByLayerStartResolver =
    Map<String, ElementState> Function(
      DrawStateView view,
      int? dynamicLayerStartIndex,
    );

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
/// cases we can reuse layer split metadata from the previous render key and
/// rebuild only the dynamic preview subset for the new state.
@immutable
class InteractionDynamicSceneSnapshot {
  InteractionDynamicSceneSnapshot({
    required Map<String, ElementState> previewElementsById,
    required Set<String>? dynamicPreviewElementIds,
    required Set<String> optimizedDynamicElementIds,
    required this.optimizedSceneHasPotentialOccluders,
    required this.dynamicLayerStartIndex,
    required this.rendersWholeElementScene,
    required this.highlightMaskLayer,
    required this.highlightMaskConfig,
    required this.watermarkLayer,
    required this.watermarkConfig,
  }) : previewElementsById = Map<String, ElementState>.unmodifiable(
         previewElementsById,
       ),
       dynamicPreviewElementIds = dynamicPreviewElementIds == null
           ? null
           : Set<String>.unmodifiable(dynamicPreviewElementIds),
       optimizedDynamicElementIds = Set<String>.unmodifiable(
         optimizedDynamicElementIds,
       );

  final Map<String, ElementState> previewElementsById;
  final Set<String>? dynamicPreviewElementIds;
  final Set<String> optimizedDynamicElementIds;
  final bool optimizedSceneHasPotentialOccluders;
  final int? dynamicLayerStartIndex;
  final bool rendersWholeElementScene;
  final HighlightMaskLayer highlightMaskLayer;
  final HighlightMaskConfig highlightMaskConfig;
  final WatermarkLayer watermarkLayer;
  final WatermarkConfig watermarkConfig;
}

/// Resolves the dynamic-scene payload for interaction-only updates by reusing
/// split metadata from [previousRenderKey].
///
/// This avoids recomputing dynamic-scene optimization plans and highlight-mask
/// routing for every pointer frame while still rebuilding preview elements for
/// the latest state.
InteractionDynamicSceneSnapshot resolveInteractionDynamicSceneFromCachedKey({
  required DrawStateView stateView,
  required DynamicCanvasRenderKey previousRenderKey,
  required DynamicPreviewByLayerStartResolver resolvePreviewByLayerStart,
  required DynamicPreviewByOptimizedIdsResolver resolvePreviewByOptimizedIds,
  required DynamicPreviewElementIdsResolver resolveDynamicPreviewElementIds,
}) {
  final optimizedDynamicElementIds =
      previousRenderKey.optimizedDynamicElementIds;
  final optimizedSceneHasPotentialOccluders =
      optimizedDynamicElementIds.isNotEmpty &&
      previousRenderKey.optimizedSceneHasPotentialOccluders;
  final previewElementsById = optimizedDynamicElementIds.isEmpty
      ? resolvePreviewByLayerStart(
          stateView,
          previousRenderKey.dynamicLayerStartIndex,
        )
      : resolvePreviewByOptimizedIds(stateView, optimizedDynamicElementIds);
  final dynamicPreviewElementIds = resolveDynamicPreviewElementIds(
    stateView,
    previewElementsById,
  );
  return InteractionDynamicSceneSnapshot(
    previewElementsById: previewElementsById,
    dynamicPreviewElementIds: dynamicPreviewElementIds,
    optimizedDynamicElementIds: optimizedDynamicElementIds,
    optimizedSceneHasPotentialOccluders: optimizedSceneHasPotentialOccluders,
    dynamicLayerStartIndex: previousRenderKey.dynamicLayerStartIndex,
    rendersWholeElementScene: previousRenderKey.rendersWholeElementScene,
    highlightMaskLayer: previousRenderKey.highlightMaskLayer,
    highlightMaskConfig: previousRenderKey.highlightMaskConfig,
    watermarkLayer: previousRenderKey.watermarkLayer,
    watermarkConfig: previousRenderKey.watermarkConfig,
  );
}
