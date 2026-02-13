import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_rect.dart';
import 'arrow_binding_cleanup.dart';
import 'edit_computed_result.dart';

/// Shared post-geometry pipeline for standard edit operations.
///
/// After an operation applies its geometry (move/resize/rotate), the
/// remaining steps are identical: unbind arrows, resolve bindings, and
/// package the result. This helper eliminates that duplication.
class EditComputePipeline {
  const EditComputePipeline._();

  /// Runs the shared post-geometry pipeline on [updatedById].
  ///
  /// Returns `null` when [updatedById] is empty. Otherwise unbinds
  /// arrow elements, resolves bindings, and wraps everything in an
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
    bool Function(String id, ElementState element)?
        skipBindingUpdate,
  }) {
    if (updatedById.isEmpty) {
      return null;
    }

    // Work on a local copy so the caller's map is never mutated.
    final merged = Map<String, ElementState>.of(updatedById);

    final unboundArrows = unbindArrowLikeElements(
      transformedElements: merged,
      baseElements: state.domain.document.elementMap,
    );
    if (unboundArrows.isNotEmpty) {
      merged.addAll(unboundArrows);
    }

    final bindingUpdates =
        ArrowBindingResolver.instance.resolve(
      baseElements: state.domain.document.elementMap,
      updatedElements: merged,
      changedElementIds: merged.keys.toSet(),
      document: state.domain.document,
    );
    if (bindingUpdates.isNotEmpty) {
      for (final entry in bindingUpdates.entries) {
        if (skipBindingUpdate != null &&
            skipBindingUpdate(entry.key, entry.value)) {
          continue;
        }
        merged[entry.key] = entry.value;
      }
    }

    return EditComputedResult(
      updatedElements: Map.unmodifiable(merged),
      multiSelectBounds: multiSelectBounds,
      multiSelectRotation: multiSelectRotation,
    );
  }
}
