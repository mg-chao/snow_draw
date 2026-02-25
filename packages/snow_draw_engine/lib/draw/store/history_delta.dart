import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/global_elements_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_overlay_state.dart';
import '../models/selection_state.dart';
import 'snapshot.dart';

@immutable
class HistoryDelta {
  const HistoryDelta._({
    required this.beforeElements,
    required this.afterElements,
    required this.globalElementsBefore,
    required this.globalElementsAfter,
    required this.orderBefore,
    required this.orderAfter,
    required this.orderChanged,
    required this.selectionBefore,
    required this.selectionAfter,
  });

  factory HistoryDelta.fromSnapshots(
    PersistentSnapshot before,
    PersistentSnapshot after,
  ) {
    final beforeById = before.elementMap;
    final afterById = after.elementMap;

    final beforeElements = <String, ElementState>{};
    final afterElements = <String, ElementState>{};
    _collectChangedElementsByScan(
      beforeById: beforeById,
      afterById: afterById,
      beforeElements: beforeElements,
      afterElements: afterElements,
    );

    final orderBefore = List<String>.unmodifiable(before.order);
    final orderAfter = List<String>.unmodifiable(after.order);
    final orderChanged = !const ListEquality<String>().equals(
      orderBefore,
      orderAfter,
    );

    GlobalElementsState? globalElementsBefore;
    GlobalElementsState? globalElementsAfter;
    if (before.globalElements != after.globalElements) {
      globalElementsBefore = before.globalElements;
      globalElementsAfter = after.globalElements;
    }

    SelectionState? selectionBefore;
    SelectionState? selectionAfter;
    if (before.includeSelection &&
        after.includeSelection &&
        before.selection != after.selection) {
      selectionBefore = _copySelection(before.selection);
      selectionAfter = _copySelection(after.selection);
    }

    return HistoryDelta._(
      beforeElements: Map<String, ElementState>.unmodifiable(beforeElements),
      afterElements: Map<String, ElementState>.unmodifiable(afterElements),
      globalElementsBefore: globalElementsBefore,
      globalElementsAfter: globalElementsAfter,
      orderBefore: orderBefore,
      orderAfter: orderAfter,
      orderChanged: orderChanged,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
    );
  }
  final Map<String, ElementState> beforeElements;
  final Map<String, ElementState> afterElements;
  final GlobalElementsState? globalElementsBefore;
  final GlobalElementsState? globalElementsAfter;
  final List<String> orderBefore;
  final List<String> orderAfter;
  final bool orderChanged;
  final SelectionState? selectionBefore;
  final SelectionState? selectionAfter;

  bool get selectionChanged => selectionBefore != selectionAfter;

  bool get hasChanges =>
      beforeElements.isNotEmpty ||
      afterElements.isNotEmpty ||
      globalElementsBefore != null ||
      globalElementsAfter != null ||
      orderChanged ||
      selectionChanged;

  DrawState applyBackward(DrawState state) => _apply(state, forward: false);

  DrawState applyForward(DrawState state) => _apply(state, forward: true);

  DrawState _apply(DrawState state, {required bool forward}) {
    final currentElements = state.domain.document.elements;
    final currentById = {
      for (final element in currentElements) element.id: element,
    };

    final targetElements = forward ? afterElements : beforeElements;
    final removedIds = forward ? beforeElements.keys : afterElements.keys;
    final retainedIds = forward ? afterElements : beforeElements;
    final nextById = Map<String, ElementState>.from(currentById);

    for (final id in removedIds) {
      if (!retainedIds.containsKey(id)) {
        nextById.remove(id);
      }
    }
    nextById.addAll(targetElements);

    final targetOrder = forward ? orderAfter : orderBefore;

    final nextElements = <ElementState>[];
    for (final id in targetOrder) {
      final element = nextById[id];
      if (element != null) {
        nextElements.add(element);
      }
    }

    final selection = forward ? selectionAfter : selectionBefore;

    return state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(
          elements: nextElements,
          globalElements:
              (forward ? globalElementsAfter : globalElementsBefore) ??
              state.domain.document.globalElements,
        ),
        selection: selection ?? state.domain.selection,
      ),
      application: state.application.copyWith(
        interaction: const IdleState(),
        selectionOverlay: SelectionOverlayState.empty,
      ),
    );
  }
}

void _collectChangedElementsByScan({
  required Map<String, ElementState> beforeById,
  required Map<String, ElementState> afterById,
  required Map<String, ElementState> beforeElements,
  required Map<String, ElementState> afterElements,
}) {
  for (final entry in beforeById.entries) {
    final afterElement = afterById[entry.key];
    if (afterElement == null) {
      beforeElements[entry.key] = entry.value;
      continue;
    }
    if (afterElement != entry.value) {
      beforeElements[entry.key] = entry.value;
      afterElements[entry.key] = afterElement;
    }
  }

  for (final entry in afterById.entries) {
    if (!beforeById.containsKey(entry.key)) {
      afterElements[entry.key] = entry.value;
    }
  }
}

SelectionState _copySelection(SelectionState selection) => SelectionState(
  selectedIds: Set<String>.from(selection.selectedIds),
  selectionVersion: selection.selectionVersion,
);
