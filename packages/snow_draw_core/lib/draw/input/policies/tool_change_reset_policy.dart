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
  final interactionResetAction = _resolveInteractionResetAction(
    interaction: interaction,
    textElementId: textElementId,
    textDraftText: textDraftText,
    textIsNew: textIsNew,
  );
  if (interactionResetAction != null) {
    actions.add(interactionResetAction);
  }

  if (includeClearSelection) {
    actions.add(const ClearSelection());
  }
  return List<DrawAction>.unmodifiable(actions);
}

DrawAction? _resolveInteractionResetAction({
  required InteractionState interaction,
  String? textElementId,
  String? textDraftText,
  bool? textIsNew,
}) => switch (interaction) {
  TextEditingState() => FinishTextEdit(
    elementId: textElementId ?? interaction.elementId,
    text: textDraftText ?? interaction.draftData.text,
    isNew: textIsNew ?? interaction.isNew,
  ),
  CreatingState() => const CancelCreateElement(),
  EditingState() => const CancelEdit(),
  BoxSelectingState() => const CancelBoxSelect(),
  DragPendingState() => const ClearDragPending(),
  _ => null,
};
