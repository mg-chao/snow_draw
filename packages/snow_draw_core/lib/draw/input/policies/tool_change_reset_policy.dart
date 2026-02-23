import '../../actions/draw_actions.dart';
import '../../models/interaction_state.dart';

/// Resolves actions required to reset interaction state for tool changes.
List<DrawAction> resolveToolChangeResetActions({
  required InteractionState interaction,
  required bool includeClearSelection,
  String? textElementId,
  String? textDraftText,
  bool? textIsNew,
}) {
  final actions = <DrawAction>[];
  if (interaction is TextEditingState) {
    final elementId = textElementId ?? interaction.elementId;
    actions.add(
      FinishTextEdit(
        elementId: elementId,
        text: textDraftText ?? interaction.draftData.text,
        isNew: textIsNew ?? interaction.isNew,
      ),
    );
  } else if (interaction is CreatingState) {
    actions.add(const CancelCreateElement());
  } else if (interaction is EditingState) {
    actions.add(const CancelEdit());
  } else if (interaction is BoxSelectingState) {
    actions.add(const CancelBoxSelect());
  } else if (interaction is DragPendingState) {
    actions.add(const ClearDragPending());
  }

  if (includeClearSelection) {
    actions.add(const ClearSelection());
  }
  return List<DrawAction>.unmodifiable(actions);
}
