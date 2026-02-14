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
  ClearSelection _ => _handleClearSelection(state, context),
  SelectAll _ => _handleSelectAll(state, context),
  _ => null,
};

DrawState _handleSelectElement(
  DrawState state,
  SelectElement action,
  SelectionReducerDeps context,
) {
  final element = state.domain.document.getElementById(action.elementId);
  if (element == null) {
    context.log.store.warning('Selection failed: element not found', {
      'action': action.runtimeType.toString(),
      'elementId': action.elementId,
    });
    final eventBus = context.eventBus;
    if (eventBus != null && eventBus.hasListeners) {
      eventBus.emit(
        ValidationFailedEvent(
          action: action.runtimeType.toString(),
          reason: 'Element not found',
          details: {'elementId': action.elementId},
        ),
      );
    }
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

DrawState _handleClearSelection(DrawState state, SelectionReducerDeps _) =>
    applySelectionChange(state, const {});

DrawState _handleSelectAll(DrawState state, SelectionReducerDeps _) =>
    applySelectionChange(
      state,
      state.domain.document.elements.map((e) => e.id).toSet(),
    );
