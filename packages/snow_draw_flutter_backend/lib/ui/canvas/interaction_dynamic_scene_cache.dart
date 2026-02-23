import 'package:snow_draw_core/snow_draw_core.dart' as core;
import 'package:snow_draw_core/snow_draw_core.dart';

import 'render_keys.dart';

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

/// Backward-compatible alias for core interaction dynamic snapshots.
typedef InteractionDynamicSceneSnapshot = core.InteractionDynamicSceneSnapshot;

/// Adapter that keeps the previous backend function signature while routing
/// implementation ownership to core.
InteractionDynamicSceneSnapshot resolveInteractionDynamicSceneFromCachedKey({
  required DrawStateView stateView,
  required DynamicCanvasRenderKey previousRenderKey,
  required DynamicPreviewResolver resolvePreviewElements,
  required DynamicPreviewByOptimizedIdsResolver resolvePreviewByOptimizedIds,
  required DynamicPreviewElementIdsResolver resolveDynamicPreviewElementIds,
}) {
  final metadata = CachedInteractionDynamicMetadata(
    optimizedDynamicElementIds: previousRenderKey.optimizedDynamicElementIds,
    optimizedSceneHasPotentialOccluders:
        previousRenderKey.optimizedSceneHasPotentialOccluders,
    isHighlightMaskVisible: previousRenderKey.isHighlightMaskVisible,
    highlightMaskConfig: previousRenderKey.highlightMaskConfig,
    isWatermarkVisible: previousRenderKey.isWatermarkVisible,
    watermarkConfig: previousRenderKey.watermarkConfig,
  );
  return core.resolveInteractionDynamicSceneFromCachedKey(
    stateView: stateView,
    cachedMetadata: metadata,
    resolvePreviewElements: resolvePreviewElements,
    resolvePreviewByOptimizedIds: resolvePreviewByOptimizedIds,
    resolveDynamicPreviewElementIds: resolveDynamicPreviewElementIds,
  );
}
