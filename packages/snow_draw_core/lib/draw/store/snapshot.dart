import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_state.dart';

abstract interface class HistorySnapshot {
  List<ElementState> get elements;
  Map<String, ElementState> get elementMap;
  SelectionState get selection;
  bool get includeSelection;
  List<String>? get order;
}

@immutable
class PersistentSnapshot implements HistorySnapshot {
  PersistentSnapshot({
    required this.elements,
    required this.selection,
    required this.includeSelection,
    Map<String, ElementState>? elementMap,
  }) : elementMap = Map<String, ElementState>.unmodifiable(
         elementMap ?? {for (final element in elements) element.id: element},
       );

  factory PersistentSnapshot.fromState(
    DrawState state, {
    bool includeSelection = true,
  }) => PersistentSnapshot(
    elements: state.domain.document.elements,
    elementMap: state.domain.document.elementMap,
    selection: includeSelection
        ? state.domain.selection
        : const SelectionState(),
    includeSelection: includeSelection,
  );
  @override
  final List<ElementState> elements;
  @override
  final Map<String, ElementState> elementMap;
  @override
  final SelectionState selection;
  @override
  final bool includeSelection;

  DrawState applyTo(DrawState state) => state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: elements),
      selection: includeSelection ? selection : state.domain.selection,
    ),
    application: state.application.copyWith(interaction: const IdleState()),
  );

  @override
  List<String>? get order => elements.map((element) => element.id).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentSnapshot &&
          // Use deep equality rather than identical().
          const ListEquality<ElementState>().equals(elements, other.elements) &&
          includeSelection == other.includeSelection &&
          (!includeSelection || selection == other.selection);

  @override
  int get hashCode => Object.hash(
    const ListEquality<ElementState>().hash(elements),
    includeSelection,
    includeSelection ? selection : null,
  );

  @override
  String toString() =>
      'PersistentSnapshot('
      'elements: ${elements.length}, '
      'includeSelection: $includeSelection'
      ')';
}

@immutable
class IncrementalSnapshot implements HistorySnapshot {
  IncrementalSnapshot({
    required Map<String, ElementState> elementsById,
    required this.selection,
    required this.includeSelection,
    this.order,
  }) : elementMap = Map<String, ElementState>.unmodifiable(elementsById),
       elements = List<ElementState>.unmodifiable(elementsById.values);
  @override
  final List<ElementState> elements;

  @override
  final Map<String, ElementState> elementMap;

  @override
  final SelectionState selection;

  @override
  final bool includeSelection;

  @override
  final List<String>? order;

  @override
  String toString() =>
      'IncrementalSnapshot('
      'elements: ${elements.length}, '
      'includeSelection: $includeSelection, '
      'order: ${order?.length ?? 0}'
      ')';
}
