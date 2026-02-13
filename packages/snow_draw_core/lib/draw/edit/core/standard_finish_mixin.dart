import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../../models/selection_overlay_state.dart';
import '../../types/edit_context.dart';
import '../../types/edit_transform.dart';
import '../apply/edit_apply.dart';
import '../preview/edit_preview.dart';
import 'edit_computed_result.dart';
import 'edit_operation.dart';
import 'edit_operation_helpers.dart';

/// Eliminates the duplicated finish/preview boilerplate in edit operations.
///
/// Subclasses implement [computeResult] for operation-specific geometry
/// and [updateOverlay] for operation-specific multi-select overlay
/// updates. The mixin handles the shared commit and preview logic.
///
/// Operations that need different geometry for finish vs. preview (e.g.
/// arrow point deletion on commit) can override [computeFinishResult].
/// When not overridden, [finish] delegates to [computeResult].
mixin StandardFinishMixin on EditOperation {
  /// Computes the geometry result for this operation.
  ///
  /// Returns `null` when the transform is identity or validation fails,
  /// signaling that no changes should be applied.
  ///
  /// Used by [buildPreview] and, unless [computeFinishResult] is
  /// overridden, also by [finish].
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  });

  /// Computes the geometry result specifically for [finish].
  ///
  /// Override this when the committed result differs from the preview
  /// (e.g. point deletion that only happens on commit). The default
  /// delegates to [computeResult].
  EditComputedResult? computeFinishResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => computeResult(state: state, context: context, transform: transform);

  /// Returns the updated [SelectionOverlayState] after committing.
  ///
  /// Only called for multi-select contexts. Single-select operations
  /// pass through the current overlay unchanged.
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  });

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final result = computeFinishResult(
      state: state,
      context: context,
      transform: transform,
    );
    if (result == null) {
      return state.copyWith(application: state.application.toIdle());
    }

    final newElements = EditApply.replaceElementsById(
      elements: state.domain.document.elements,
      replacementsById: result.updatedElements,
    );

    final overlay = context.isMultiSelect
        ? updateOverlay(
            current: state.application.selectionOverlay,
            result: result,
            context: context,
          )
        : state.application.selectionOverlay;

    final nextDomain = state.domain.copyWith(
      document: state.domain.document.copyWith(elements: newElements),
    );
    final nextApplication = state.application.copyWith(
      interaction: const IdleState(),
      selectionOverlay: overlay,
    );

    return state.copyWith(domain: nextDomain, application: nextApplication);
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final result = computeResult(
      state: state,
      context: context,
      transform: transform,
    );
    if (result == null) {
      return EditPreview.none;
    }

    return buildEditPreview(
      state: state,
      context: context,
      previewElementsById: result.updatedElements,
      multiSelectBounds: result.multiSelectBounds,
      multiSelectRotation: result.multiSelectRotation,
    );
  }
}
