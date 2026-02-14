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
    bool Function(String id, ElementState element)? skipBindingUpdate,
  }) {
    if (updatedById.isEmpty) {
      return null;
    }

    var merged = updatedById;
    Map<String, ElementState>? mutableMerged;

    Map<String, ElementState> ensureMutableMerged() {
      final existing = mutableMerged;
      if (existing != null) {
        return existing;
      }
      final created = Map<String, ElementState>.of(merged);
      mutableMerged = created;
      merged = created;
      return created;
    }

    final unboundArrows = unbindArrowLikeElements(
      transformedElements: merged,
      baseElements: state.domain.document.elementMap,
    );
    if (unboundArrows.isNotEmpty) {
      ensureMutableMerged().addAll(unboundArrows);
    }

    final bindingUpdates = ArrowBindingResolver.instance.resolve(
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
        ensureMutableMerged()[entry.key] = entry.value;
      }
    }

    return EditComputedResult(
      updatedElements: Map.unmodifiable(merged),
      multiSelectBounds: multiSelectBounds,
      multiSelectRotation: multiSelectRotation,
    );
  }
}
