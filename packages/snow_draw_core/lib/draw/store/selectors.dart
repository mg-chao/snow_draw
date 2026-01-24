import 'package:collection/collection.dart';

import '../models/camera_state.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_state.dart';
import '../models/view_state.dart';
import 'selector.dart';

/// Predefined state selectors.
///
/// These selectors provide access to common state slices and can be used
/// directly in UI components for fine-grained subscriptions.

/// Select the document element list.
final documentElementsSelector = SimpleSelector<DrawState, List<ElementState>>(
  (state) => state.domain.document.elements,
  equals: (prev, next) => const ListEquality<ElementState>().equals(prev, next),
);

/// Select the view state.
final viewStateSelector = SimpleSelector<DrawState, ViewState>(
  (state) => state.application.view,
);

/// Select view transforms (zoom and pan).
final viewTransformSelector = SimpleSelector<DrawState, CameraState>(
  (state) => state.application.view.camera,
);

/// Select the selection state.
final selectionStateSelector = SimpleSelector<DrawState, SelectionState>(
  (state) => state.domain.selection,
);

/// Select the set of selected element IDs.
final selectedIdsSelector = SimpleSelector<DrawState, Set<String>>(
  (state) => state.domain.selection.selectedIds,
  equals: (prev, next) => const SetEquality<String>().equals(prev, next),
);

/// Select the list of selected elements.
final selectedElementsSelector = SimpleSelector<DrawState, List<ElementState>>(
  (state) {
    final document = state.domain.document;
    return state.domain.selection.selectedIds
        .map(document.getElementById)
        .whereType<ElementState>()
        .toList();
  },
  equals: (prev, next) => const ListEquality<ElementState>().equals(prev, next),
);

/// Select visible elements (filtering out invisible ones).
final visibleElementsSelector = SimpleSelector<DrawState, List<ElementState>>(
  (state) =>
      state.domain.document.elements.where((e) => e.opacity > 0).toList(),
  equals: (prev, next) => const ListEquality<ElementState>().equals(prev, next),
);

/// Select the element count.
final elementCountSelector = SimpleSelector<DrawState, int>(
  (state) => state.domain.document.elements.length,
);

/// Select whether any element is selected.
final hasSelectionSelector = SimpleSelector<DrawState, bool>(
  (state) => state.domain.selection.selectedIds.isNotEmpty,
);

/// Select the interaction state.
final interactionStateSelector = SimpleSelector<DrawState, InteractionState>(
  (state) => state.application.interaction,
);

/// Select whether editing mode is active.
final isEditingSelector = SimpleSelector<DrawState, bool>(
  (state) => state.application.interaction is EditingState,
);

/// Select whether creation mode is active.
final isCreatingSelector = SimpleSelector<DrawState, bool>(
  (state) => state.application.interaction is CreatingState,
);

/// Select the document version.
final documentVersionSelector = SimpleSelector<DrawState, int>(
  (state) => state.domain.document.elementsVersion,
);

/// Create a selector for a specific element.
///
/// [elementId] is the element ID to select.
/// Returns a selector that yields null if the element is missing.
StateSelector<DrawState, ElementState?> createElementSelector(
  String elementId,
) => SimpleSelector<DrawState, ElementState?>(
  (state) => state.domain.document.getElementById(elementId),
);

/// Create a selector for multiple elements.
///
/// [elementIds] is the list of element IDs to select.
/// Returns a selector that yields all found elements.
StateSelector<DrawState, List<ElementState>> createElementsSelector(
  List<String> elementIds,
) => SimpleSelector<DrawState, List<ElementState>>(
  (state) {
    final document = state.domain.document;
    return elementIds
        .map(document.getElementById)
        .whereType<ElementState>()
        .toList();
  },
  equals: (prev, next) => const ListEquality<ElementState>().equals(prev, next),
);

/// Create a selector for an element property.
///
/// [elementId] is the element ID.
/// [propertySelector] selects a property from the element.
/// Returns a selector that yields null if the element is missing.
StateSelector<DrawState, T?> createElementPropertySelector<T>(
  String elementId,
  T Function(ElementState) propertySelector,
) => SimpleSelector<DrawState, T?>((state) {
  final element = state.domain.document.getElementById(elementId);
  return element != null ? propertySelector(element) : null;
});
