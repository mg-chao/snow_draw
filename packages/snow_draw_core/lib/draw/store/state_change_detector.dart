import '../models/draw_state.dart';
import 'draw_store_interface.dart';

/// Returns tracked [DrawStateChange] values between two states.
///
/// This keeps change-detection rules centralized so event emission and
/// listener filtering always use identical semantics.
Set<DrawStateChange> computeDrawStateChanges(
  DrawState previous,
  DrawState next,
) {
  final changes = <DrawStateChange>{};

  if (hasDocumentStateChanged(previous, next)) {
    changes.add(DrawStateChange.document);
  }
  if (hasSelectionStateChanged(previous, next)) {
    changes.add(DrawStateChange.selection);
  }
  if (hasViewStateChanged(previous, next)) {
    changes.add(DrawStateChange.view);
  }
  if (hasInteractionStateChanged(previous, next)) {
    changes.add(DrawStateChange.interaction);
  }

  return changes;
}

/// Returns whether persisted document content changed.
///
/// A change is recognized only when document identity changes and the
/// `elementsVersion` counter advances.
bool hasDocumentStateChanged(DrawState previous, DrawState next) {
  final previousDocument = previous.domain.document;
  final nextDocument = next.domain.document;
  return !identical(previousDocument, nextDocument) &&
      previousDocument.elementsVersion != nextDocument.elementsVersion;
}

/// Returns whether persisted selection changed.
///
/// A change is recognized only when selection identity changes and the
/// `selectionVersion` counter advances.
bool hasSelectionStateChanged(DrawState previous, DrawState next) {
  final previousSelection = previous.domain.selection;
  final nextSelection = next.domain.selection;
  return !identical(previousSelection, nextSelection) &&
      previousSelection.selectionVersion != nextSelection.selectionVersion;
}

/// Returns whether view state changed.
bool hasViewStateChanged(DrawState previous, DrawState next) {
  final previousView = previous.application.view;
  final nextView = next.application.view;
  return !identical(previousView, nextView) && previousView != nextView;
}

/// Returns whether interaction state changed.
bool hasInteractionStateChanged(DrawState previous, DrawState next) {
  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  return !identical(previousInteraction, nextInteraction) &&
      previousInteraction != nextInteraction;
}
