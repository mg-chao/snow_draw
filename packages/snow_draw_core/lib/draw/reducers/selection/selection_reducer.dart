import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../core/reducer_utils.dart';

DrawState? selectionReducer(
  DrawState state,
  DrawAction action,
  SelectionReducerDeps context,
) => switch (action) {
  final SelectElement a => _handleSelectElement(state, a, context),
  ClearSelection _ => applySelectionChange(state, const <String>{}),
  SelectAll _ => applySelectionChange(
    state,
    state.domain.document.elements.map((e) => e.id).toSet(),
  ),
  _ => null,
};

DrawState _handleSelectElement(
  DrawState state,
  SelectElement action,
  SelectionReducerDeps context,
) {
  if (state.domain.document.getElementById(action.elementId) == null) {
    context.log.store.warning('Selection failed: element not found', {
      'action': action.runtimeType.toString(),
      'elementId': action.elementId,
    });
    context.eventBus?.emitLazy(
      () => ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'Element not found',
        details: {'elementId': action.elementId},
      ),
    );
    return state;
  }

  if (!action.addToSelection) {
    return applySelectionChange(state, {action.elementId});
  }

  final nextSelectedIds = {...state.domain.selection.selectedIds};
  if (!nextSelectedIds.add(action.elementId)) {
    nextSelectedIds.remove(action.elementId);
  }
  return applySelectionChange(state, nextSelectedIds);
}
