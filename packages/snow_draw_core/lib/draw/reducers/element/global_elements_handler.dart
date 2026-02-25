import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../models/draw_state.dart';

DrawState handleUpdateGlobalElements(
  DrawState state,
  UpdateGlobalElements action,
  DrawContext _,
) {
  final currentDocument = state.domain.document;
  final nextGlobalElements = currentDocument.globalElements.copyWith(
    highlightMask: action.highlightMask,
    watermark: action.watermark,
  );
  if (identical(nextGlobalElements, currentDocument.globalElements)) {
    return state;
  }

  return state.copyWith(
    domain: state.domain.copyWith(
      document: currentDocument.copyWith(globalElements: nextGlobalElements),
    ),
  );
}
