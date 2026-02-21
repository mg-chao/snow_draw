import 'package:snow_draw_core/snow_draw_core.dart';

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
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      _isLightweightLineCreatingMutationOnly(
        previous: previousCreating,
        next: nextCreating,
      ),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      _isLightweightLineEditingMutationOnly(
        previous: previousEditing,
        next: nextEditing,
        document: next.domain.document,
      ),
    _ => false,
  };
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
}) {
  if (!_isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  if (previousInteraction is! EditingState ||
      nextInteraction is! EditingState) {
    return false;
  }

  return _isLightweightLineEditingMutationOnly(
    previous: previousInteraction,
    next: nextInteraction,
    document: next.domain.document,
  );
}

bool _isInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next) || !identical(previous.domain, next.domain)) {
    return false;
  }

  final previousApplication = previous.application;
  final nextApplication = next.application;
  return previousApplication.view == nextApplication.view &&
      previousApplication.selectionOverlay == nextApplication.selectionOverlay;
}

bool _isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

bool _isLightweightLineCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! LineData ||
      next.elementData is! LineData ||
      !_isSameLineCreationSession(previous, next)) {
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
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!_isSameEditSession(previous, next) ||
      !_isLightweightLineContext(
        context: previous.context,
        document: document,
      )) {
    return false;
  }

  return previous.currentTransform != next.currentTransform ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isLightweightLineContext({
  required EditContext context,
  required DocumentState document,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (selectedIds.isEmpty) {
    return false;
  }

  return selectedIds.every((elementId) {
    final data = document.getElementById(elementId)?.data;
    return data is LineData || data is FreeDrawData;
  });
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
