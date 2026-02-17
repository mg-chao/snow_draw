import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/types/edit_context.dart';

/// Returns true when only an in-progress lightweight line edit changed.
///
/// Lightweight line edits are edit sessions where every selected element is
/// either a [LineData] or [FreeDrawData]. These element types are not arrow
/// binding targets, so transform-only updates can repaint the dynamic layer
/// without rebuilding static-scene snapshots.
bool isLightweightLineEditMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next)) {
    return false;
  }
  if (!identical(previous.domain, next.domain)) {
    return false;
  }

  final previousApplication = previous.application;
  final nextApplication = next.application;
  if (previousApplication.view != nextApplication.view ||
      previousApplication.selectionOverlay !=
          nextApplication.selectionOverlay) {
    return false;
  }

  final previousInteraction = previousApplication.interaction;
  final nextInteraction = nextApplication.interaction;
  if (previousInteraction is! EditingState ||
      nextInteraction is! EditingState) {
    return false;
  }
  if (!_isSameEditSession(previousInteraction, nextInteraction)) {
    return false;
  }
  if (!_isLightweightLineContext(
        context: previousInteraction.context,
        document: next.domain.document,
      ) ||
      !_isLightweightLineContext(
        context: nextInteraction.context,
        document: next.domain.document,
      )) {
    return false;
  }

  return previousInteraction.currentTransform !=
          nextInteraction.currentTransform ||
      !_listEquals(previousInteraction.snapGuides, nextInteraction.snapGuides);
}

bool _isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

bool _isLightweightLineContext({
  required EditContext context,
  required DocumentState document,
}) {
  if (context.selectedIdsAtStart.isEmpty) {
    return false;
  }
  for (final elementId in context.selectedIdsAtStart) {
    final element = document.getElementById(elementId);
    if (element == null) {
      return false;
    }
    final data = element.data;
    if (data is LineData || data is FreeDrawData) {
      continue;
    }
    return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
