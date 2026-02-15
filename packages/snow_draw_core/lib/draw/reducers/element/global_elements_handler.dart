import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../models/draw_state.dart';

DrawState handleUpdateGlobalElements(
  DrawState state,
  UpdateGlobalElements action,
  ElementReducerDeps _,
) {
  if (!action.hasUpdates) {
    return state;
  }

  final document = state.domain.document;
  final currentGlobalElements = document.globalElements;
  final nextGlobalElements = currentGlobalElements.copyWith(
    highlightMask: action.highlightMask,
    watermark: action.watermark,
  );
  if (nextGlobalElements == currentGlobalElements) {
    return state;
  }

  return state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(globalElements: nextGlobalElements),
    ),
  );
}
