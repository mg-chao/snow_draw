import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../core/edit_errors.dart';
import '../edit_operation_registry_interface.dart';
import 'edit_preview.dart';

/// Computes the "effective" (preview) elements and selection overlay during
/// an edit session.
///
/// In the preview/commit architecture:
/// - `state.domain.document.elements` remains persistent (unchanged) during
///   editing
/// - `state.application.interaction` carries the session transform
///   (dx/dy/angle/bounds...)
/// - rendering and hit-testing should use this effective preview
class EditPreviewEngine {
  EditPreviewEngine();

  EditPreview build({
    required DrawState state,
    required EditOperationRegistry editOperations,
  }) {
    final interaction = state.application.interaction;
    if (interaction is! EditingState) {
      return EditPreview.none;
    }

    final operation = editOperations.getOperation(interaction.operationId);
    if (operation == null) {
      return EditPreview.none;
    }

    try {
      return operation.buildPreview(
        state: state,
        context: interaction.context,
        transform: interaction.currentTransform,
      );
    } on EditError {
      return EditPreview.none;
    }
  }
}
