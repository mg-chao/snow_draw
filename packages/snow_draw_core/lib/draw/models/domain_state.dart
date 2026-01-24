import 'package:meta/meta.dart';

import 'document_state.dart';
import 'element_state.dart';
import 'selection_state.dart';

/// Domain-layer state.
///
/// Includes all state that must be persisted and participates in undo/redo.
/// This is a pure data layer with no UI or interaction state.
@immutable
class DomainState {
  const DomainState({
    required this.document,
    this.selection = const SelectionState(),
  });

  /// Factory method: create an empty domain state.
  factory DomainState.empty() => DomainState(document: DocumentState());

  /// Document data (element list, versions, and so on).
  final DocumentState document;

  /// Selected element ID set.
  ///
  /// Note: only the IDs are stored, not the selection overlay's visual state.
  /// Selection participates in undo/redo, but overlay rotation and similar
  /// do not.
  final SelectionState selection;

  /// Convenient access to the element list.
  List<ElementState> get elements => document.elements;

  /// Elements version.
  int get elementsVersion => document.elementsVersion;

  /// Whether any element is selected.
  bool get hasSelection => selection.hasSelection;

  /// Number of selected elements.
  int get selectionCount => selection.count;

  /// Whether this is a single selection.
  bool get isSingleSelection => selection.isSingleSelect;

  /// Whether this is a multi-selection.
  bool get isMultiSelection => selection.isMultiSelect;
  Set<String> get selectedIds => selection.selectedIds;
  int get selectionVersion => selection.selectionVersion;
  DomainState copyWith({DocumentState? document, SelectionState? selection}) =>
      DomainState(
        document: document ?? this.document,
        selection: selection ?? this.selection,
      );

  /// Clear selection.
  DomainState clearSelection() {
    if (!selection.hasSelection) {
      return this;
    }
    return copyWith(selection: selection.cleared());
  }

  /// Set the selection.
  DomainState withSelection(Set<String> ids) =>
      copyWith(selection: selection.withSelectedIds(ids));

  /// Select a single element.
  DomainState withSelected(String elementId) =>
      copyWith(selection: selection.withSelected(elementId));

  /// Add an element to the selection.
  DomainState withAdded(String elementId) =>
      copyWith(selection: selection.withAdded(elementId));

  /// Remove an element from the selection.
  DomainState withRemoved(String elementId) =>
      copyWith(selection: selection.withRemoved(elementId));

  /// Toggle element selection.
  DomainState withToggled(String elementId) =>
      copyWith(selection: selection.withToggled(elementId));

  /// Update the element list.
  DomainState withElements(List<ElementState> elements) =>
      copyWith(document: document.copyWith(elements: elements));

  /// Equality comparison for undo/redo.
  ///
  /// Only compare fields that participate in history.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! DomainState) {
      return false;
    }
    return document == other.document && selection == other.selection;
  }

  @override
  int get hashCode => Object.hash(document, selection);

  @override
  String toString() =>
      'DomainState(elements: ${elements.length}, '
      'selectedIds: ${selectedIds.length})';
}
