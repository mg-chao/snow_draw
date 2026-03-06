import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../elements/types/arrow/arrow_core_bridge.dart';
import '../../elements/types/arrow/arrow_core_ops.dart';
import '../../elements/types/connector/connector_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_rect.dart';
import '../../utils/combined_element_lookup.dart';
import 'edit_computed_result.dart';

/// Shared post-geometry pipeline for standard edit operations.
///
/// After an operation applies its geometry (move/resize/rotate), the
/// remaining steps are identical: prune invalid transformed bindings via
/// arrow-core lifecycle rules, resolve endpoint bindings, and package the
/// result. This helper eliminates that duplication.
class EditComputePipeline {
  const EditComputePipeline._();

  /// Runs the shared post-geometry pipeline on [updatedById].
  ///
  /// Returns `null` when [updatedById] is empty. Otherwise synchronizes
  /// transformed arrow bindings through arrow-core, resolves bindings,
  /// and wraps everything in an
  /// [EditComputedResult].
  ///
  /// [skipBindingUpdate] is an optional predicate that lets callers
  /// exclude specific elements from binding resolution (e.g. rotate
  /// skips selected elbow arrows).
  static EditComputedResult? finalize({
    required DrawState state,
    required Map<String, ElementState> updatedById,
    DrawRect? multiSelectBounds,
    double? multiSelectRotation,
    bool isBindingEnabled = true,
    bool Function(String id, ElementState element)? skipBindingUpdate,
  }) {
    if (updatedById.isEmpty) {
      return null;
    }

    final document = state.domain.document;
    final merged = _pruneTransformedArrowBindings(
      state: state,
      transformedElements: updatedById,
      baseElements: document.elementMap,
      isBindingEnabled: isBindingEnabled,
    );

    final bindingUpdates = ArrowBindingResolver.instance.resolve(
      baseElements: document.elementMap,
      updatedElements: merged,
      changedElementIds: merged.keys.toSet(),
      orderedElementIds: document.elements
          .map((element) => element.id)
          .toList(growable: false),
      engineContext: buildCoreEngineContext(
        zoom: state.application.view.camera.zoom,
        isBindingEnabled: isBindingEnabled,
      ),
      skipArrowIds: <String>{
        for (final entry in merged.entries)
          if (entry.value.data is ConnectorData) entry.key,
      },
    );
    for (final entry in bindingUpdates.updatedElements.entries) {
      if (skipBindingUpdate?.call(entry.key, entry.value) ?? false) {
        continue;
      }
      merged[entry.key] = entry.value;
    }

    return EditComputedResult(
      updatedElements: Map.unmodifiable(merged),
      orderedElementIds: bindingUpdates.orderedElementIds,
      multiSelectBounds: multiSelectBounds,
      multiSelectRotation: multiSelectRotation,
    );
  }
}

Map<String, ElementState> _pruneTransformedArrowBindings({
  required DrawState state,
  required Map<String, ElementState> transformedElements,
  required Map<String, ElementState> baseElements,
  required bool isBindingEnabled,
}) {
  if (transformedElements.isEmpty) {
    return transformedElements;
  }

  final merged = Map<String, ElementState>.of(transformedElements);
  final lookup = CombinedElementLookup(base: baseElements, overlay: merged);
  final transformedArrows = collectCoreArrowStatesWithSources(
    transformedElements.values,
    onlyBoundArrows: true,
  );
  if (transformedArrows.arrows.isEmpty) {
    return merged;
  }

  final retainedBindableIds = <String>[
    for (final id in transformedElements.keys)
      if (lookup[id] case final element? when isArrowBindableElement(element))
        id,
  ];
  final syncResult = syncCoreBindingsAfterBindablePrune(
    arrows: transformedArrows.arrows,
    bindables: collectCoreBindableRelations(lookup.values),
    geometryBindables: collectCoreBindables(lookup.values),
    retainedBindableIds: retainedBindableIds,
    context: buildCoreEngineContext(
      zoom: state.application.view.camera.zoom,
      isBindingEnabled: isBindingEnabled,
    ),
    options: const <String, dynamic>{'recomputeElbows': true},
  );
  if (syncResult.arrowPatches.isEmpty) {
    return merged;
  }

  final patchedById = applyCoreArrowPatchesToSources(
    patches: syncResult.arrowPatches,
    sources: transformedArrows.sources,
  );
  for (final entry in patchedById.entries) {
    merged[entry.key] = entry.value;
  }
  return merged;
}
