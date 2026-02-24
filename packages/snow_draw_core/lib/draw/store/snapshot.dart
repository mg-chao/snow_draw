import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/global_elements_state.dart';
import '../models/selection_state.dart';

const _elementListEquality = ListEquality<ElementState>();

abstract interface class HistorySnapshot {
  List<ElementState> get elements;
  Map<String, ElementState> get elementMap;
  GlobalElementsState get globalElements;
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
    this.globalElements = const GlobalElementsState(),
    Map<String, ElementState>? elementMap,
  }) : elementMap = Map<String, ElementState>.unmodifiable(
         elementMap ?? {for (final element in elements) element.id: element},
       );

  factory PersistentSnapshot.fromState(
    DrawState state, {
    bool includeSelection = true,
  }) => PersistentSnapshot(
    elements: state.domain.document.elements,
    globalElements: state.domain.document.globalElements,
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
  final GlobalElementsState globalElements;
  @override
  final SelectionState selection;
  @override
  final bool includeSelection;

  @override
  List<String>? get order => elements.map((element) => element.id).toList();

  SelectionState? get _comparableSelection =>
      includeSelection ? selection : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentSnapshot &&
          _elementListEquality.equals(elements, other.elements) &&
          globalElements == other.globalElements &&
          includeSelection == other.includeSelection &&
          _comparableSelection == other._comparableSelection;

  @override
  int get hashCode => Object.hash(
    _elementListEquality.hash(elements),
    globalElements,
    includeSelection,
    _comparableSelection,
  );

  @override
  String toString() =>
      'PersistentSnapshot('
      'elements: ${elements.length}, '
      'includeSelection: $includeSelection'
      ')';
}
