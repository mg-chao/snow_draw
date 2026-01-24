import '../../config/draw_config.dart';
import '../../history/history_metadata.dart';
import '../../history/recordable.dart';
import '../../models/draw_state.dart';
import '../../types/draw_point.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../preview/edit_preview.dart';
import 'edit_modifiers.dart';
import 'edit_operation_params.dart';
import 'edit_result.dart';

/// Unified edit-domain operation interface (move/resize/rotate/...).
///
/// This is intentionally **not** the same concept as an input-layer "intent".
abstract class EditOperation {
  const EditOperation();

  /// Stable id used by the operation registry and edit session.
  EditOperationId get id;

  /// Whether this operation should record history on finish.
  bool get recordsHistory => true;

  /// Creates history metadata for the current context/transform.
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) => HistoryMetadata(
    description: '$id operation',
    recordType: HistoryRecordType.edit,
    affectedElementIds: context.selectedIdsAtStart,
  );

  /// Creates an immutable edit context snapshot for a new edit session.
  EditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  });

  /// Returns the initial transform for a newly started edit session.
  EditTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  });

  /// Updates the edit session's transform. Must not mutate elements.
  EditUpdateResult<EditTransform> update({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
    required DrawConfig config,
  });

  /// Commits the current transform into persistent state (elements/selection).
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  });

  /// Cancels the current edit session and returns to idle state.
  ///
  /// Default implementation simply transitions to idle without modifying
  /// elements. Override if the operation needs custom cleanup.
  DrawState cancel({required DrawState state, required EditContext context}) =>
      state.copyWith(application: state.application.toIdle());

  /// Builds the effective preview used by rendering and hit-testing.
  ///
  /// This must be consistent with [finish] (same geometry source of truth).
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  });
}
