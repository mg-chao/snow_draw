import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../models/document_state.dart';
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

    final document = state.domain.document;
    final changeKind = _resolveChangeKind(updatedById);
    if (!_shouldRunArrowBindingPipeline(
      document: document,
      updatedIds: updatedById.keys,
      hasArrowLikeUpdate: changeKind.hasArrowLikeUpdate,
      hasBindableTargetUpdate: changeKind.hasBindableTargetUpdate,
    )) {
      return EditComputedResult(
        updatedElements: Map<String, ElementState>.unmodifiable(updatedById),
        multiSelectBounds: multiSelectBounds,
        multiSelectRotation: multiSelectRotation,
      );
    }

    final merged = Map<String, ElementState>.of(updatedById);

    if (changeKind.hasArrowLikeUpdate) {
      merged.addAll(
        unbindArrowLikeElements(
          transformedElements: merged,
          baseElements: document.elementMap,
        ),
      );
    }

    final bindingUpdates = ArrowBindingResolver.instance.resolve(
      baseElements: document.elementMap,
      updatedElements: merged,
      changedElementIds: merged.keys.toSet(),
      document: document,
    );
    for (final entry in bindingUpdates.entries) {
      if (skipBindingUpdate?.call(entry.key, entry.value) ?? false) {
        continue;
      }
      merged[entry.key] = entry.value;
    }

    return EditComputedResult(
      updatedElements: Map.unmodifiable(merged),
      multiSelectBounds: multiSelectBounds,
      multiSelectRotation: multiSelectRotation,
    );
  }

  static bool _shouldRunArrowBindingPipeline({
    required DocumentState document,
    required Iterable<String> updatedIds,
    required bool hasArrowLikeUpdate,
    required bool hasBindableTargetUpdate,
  }) {
    if (hasArrowLikeUpdate) {
      return true;
    }

    if (!hasBindableTargetUpdate) {
      return false;
    }

    return document.hasArrowBoundToAny(updatedIds);
  }

  static ({bool hasArrowLikeUpdate, bool hasBindableTargetUpdate})
  _resolveChangeKind(Map<String, ElementState> updatedById) {
    var hasArrowLikeUpdate = false;
    var hasBindableTargetUpdate = false;
    for (final element in updatedById.values) {
      if (element.data is ArrowLikeData) {
        hasArrowLikeUpdate = true;
      } else if (ArrowBindingUtils.isBindableTarget(element)) {
        hasBindableTargetUpdate = true;
      }

      if (hasArrowLikeUpdate && hasBindableTargetUpdate) {
        break;
      }
    }
    return (
      hasArrowLikeUpdate: hasArrowLikeUpdate,
      hasBindableTargetUpdate: hasBindableTargetUpdate,
    );
  }
}
