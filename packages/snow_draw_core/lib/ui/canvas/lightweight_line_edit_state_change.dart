import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/types/edit_context.dart';

/// Returns true when only an in-progress lightweight line interaction changed.
///
/// Lightweight line edits are edit sessions where every selected element is
/// either a [LineData] or [FreeDrawData]. These element types are not arrow
/// binding targets, so transform-only updates can repaint the dynamic layer
/// without rebuilding static-scene snapshots.
///
/// This fast path also covers [LineData] creation updates, where only the
/// in-progress creating interaction changes and the persistent document stays
/// unchanged.
bool isLightweightLineInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (!_isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  final document = next.domain.document;

  if (previousInteraction is CreatingState &&
      nextInteraction is CreatingState) {
    return _isLightweightLineCreatingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
    );
  }

  if (previousInteraction is EditingState && nextInteraction is EditingState) {
    return _isLightweightLineEditingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
      document: document,
    );
  }

  return false;
}

/// Returns true when [interaction] is an editing session limited to
/// lightweight line-compatible element types.
///
/// Lightweight line contexts include only [LineData] and [FreeDrawData]
/// selections, which can use the dynamic-layer fast path safely.
bool isLightweightLineEditingInteraction({
  required InteractionState interaction,
  required DocumentState document,
}) =>
    interaction is EditingState &&
    isLightweightLineEditContext(
      context: interaction.context,
      document: document,
    );

/// Returns true when [context] selects only lightweight line-compatible
/// element types in [document].
bool isLightweightLineEditContext({
  required EditContext context,
  required DocumentState document,
}) => _isLightweightLineContext(context: context, document: document);

/// Returns true when only an in-progress lightweight line edit changed.
///
/// Prefer [isLightweightLineInteractionMutationOnly] for create+edit flows.
bool isLightweightLineEditMutationOnly({
  required DrawState previous,
  required DrawState next,
}) =>
    _isInteractionMutationOnly(previous: previous, next: next) &&
    _isLightweightLineEditingMutationOnly(
      previous: previous.application.interaction,
      next: next.application.interaction,
      document: next.domain.document,
    );

bool _isInteractionMutationOnly({
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
  return true;
}

bool _isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

bool _isLightweightLineCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! LineData || next.elementData is! LineData) {
    return false;
  }
  if (!_isSameLineCreationSession(previous, next)) {
    return false;
  }
  return previous.currentRect != next.currentRect ||
      previous.creationMode != next.creationMode ||
      previous.elementData != next.elementData ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameLineCreationSession(CreatingState previous, CreatingState next) =>
    previous.elementId == next.elementId &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

bool _isLightweightLineEditingMutationOnly({
  required InteractionState previous,
  required InteractionState next,
  required DocumentState document,
}) {
  if (previous is! EditingState || next is! EditingState) {
    return false;
  }
  if (!_isSameEditSession(previous, next)) {
    return false;
  }
  if (!_isLightweightLineContext(
        context: previous.context,
        document: document,
      ) ||
      !_isLightweightLineContext(context: next.context, document: document)) {
    return false;
  }

  return previous.currentTransform != next.currentTransform ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

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
