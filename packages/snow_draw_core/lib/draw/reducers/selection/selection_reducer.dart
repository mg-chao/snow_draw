import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../core/reducer_utils.dart';

DrawState? selectionReducer(
  DrawState state,
  DrawAction action,
  DrawContext context,
) => switch (action) {
  final SelectElement a => _handleSelectElement(state, a, context),
  ClearSelection _ => _handleClearSelection(state, context),
  SelectAll _ => _handleSelectAll(state, context),
  _ => null,
};

DrawState _handleSelectElement(
  DrawState state,
  SelectElement action,
  DrawContext context,
) {
  if (state.domain.document.getElementById(action.elementId) == null) {
    context.log.store.warning('Selection failed: element not found', {
      'action': action.runtimeType.toString(),
      'elementId': action.elementId,
    });
    context.eventBus?.emit(
      ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'Element not found',
        details: {'elementId': action.elementId},
      ),
    );
    return state;
  }

  Set<String> newSelectedIds;
  if (!action.addToSelection) {
    newSelectedIds = {action.elementId};
  } else {
    newSelectedIds = {...state.domain.selection.selectedIds};
    if (newSelectedIds.contains(action.elementId)) {
      newSelectedIds.remove(action.elementId);
    } else {
      newSelectedIds.add(action.elementId);
    }
  }

  return applySelectionChange(state, newSelectedIds);
}

DrawState _handleClearSelection(DrawState state, DrawContext _) =>
    state.copyWith(
      domain: state.domain.copyWith(
        selection: state.domain.selection.cleared(),
      ),
    );

DrawState _handleSelectAll(DrawState state, DrawContext _) =>
    applySelectionChange(
      state,
      state.domain.document.elements.map((e) => e.id).toSet(),
    );
