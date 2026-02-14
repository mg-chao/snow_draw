import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_overlay_state.dart';
import '../models/selection_state.dart';
import 'history_change_set.dart';
import 'snapshot.dart';

@immutable
class HistoryDelta {
  const HistoryDelta._({
    required this.beforeElements,
    required this.afterElements,
    required this.orderBefore,
    required this.orderAfter,
    required this.selectionBefore,
    required this.selectionAfter,
    required this.reindexZIndices,
  });

  factory HistoryDelta.fromData({
    required Map<String, ElementState> beforeElements,
    required Map<String, ElementState> afterElements,
    List<String>? orderBefore,
    List<String>? orderAfter,
    SelectionState? selectionBefore,
    SelectionState? selectionAfter,
    bool reindexZIndices = false,
  }) => HistoryDelta._(
    beforeElements: Map<String, ElementState>.unmodifiable(beforeElements),
    afterElements: Map<String, ElementState>.unmodifiable(afterElements),
    orderBefore: orderBefore == null
        ? null
        : List<String>.unmodifiable(orderBefore),
    orderAfter: orderAfter == null
        ? null
        : List<String>.unmodifiable(orderAfter),
    selectionBefore: selectionBefore == null
        ? null
        : _copySelection(selectionBefore),
    selectionAfter: selectionAfter == null
        ? null
        : _copySelection(selectionAfter),
    reindexZIndices: reindexZIndices,
  );

  factory HistoryDelta.fromSnapshots(
    HistorySnapshot before,
    HistorySnapshot after, {
    HistoryChangeSet? changes,
  }) {
    final beforeById = before.elementMap;
    final afterById = after.elementMap;

    final beforeElements = <String, ElementState>{};
    final afterElements = <String, ElementState>{};

    // Reordering actions can implicitly update many elements (for example
    // z-index reindexing), so targeted element diffing is only safe when
    // order is unchanged.
    final useTargetedElementDiff =
        changes != null && changes.hasElementChanges && !changes.orderChanged;

    if (useTargetedElementDiff) {
      _collectChangedElementsById(
        beforeById: beforeById,
        afterById: afterById,
        changedIds: changes.allElementIds,
        beforeElements: beforeElements,
        afterElements: afterElements,
      );
    } else {
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

    final includeOrder = changes?.orderChanged ?? true;
    List<String>? orderBefore;
    List<String>? orderAfter;
    if (includeOrder) {
      final beforeOrder = before.order;
      final afterOrder = after.order;
      if (beforeOrder != null && afterOrder != null) {
        final orderChanged = !const ListEquality<String>().equals(
          beforeOrder,
          afterOrder,
        );
        if (orderChanged) {
          orderBefore = List<String>.unmodifiable(beforeOrder);
          orderAfter = List<String>.unmodifiable(afterOrder);
        }
      }
    }

    final includeSelection = before.includeSelection && after.includeSelection;
    SelectionState? selectionBefore;
    SelectionState? selectionAfter;
    if (includeSelection) {
      selectionBefore = _copySelection(before.selection);
      selectionAfter = _copySelection(after.selection);
    }

    return HistoryDelta._(
      beforeElements: Map<String, ElementState>.unmodifiable(beforeElements),
      afterElements: Map<String, ElementState>.unmodifiable(afterElements),
      orderBefore: orderBefore,
      orderAfter: orderAfter,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
      reindexZIndices: changes?.reindexZIndices ?? false,
    );
  }
  final Map<String, ElementState> beforeElements;
  final Map<String, ElementState> afterElements;
  final List<String>? orderBefore;
  final List<String>? orderAfter;
  final SelectionState? selectionBefore;
  final SelectionState? selectionAfter;
  final bool reindexZIndices;

  bool get selectionChanged =>
      selectionBefore != null &&
      selectionAfter != null &&
      selectionBefore != selectionAfter;

  bool get hasChanges =>
      beforeElements.isNotEmpty ||
      afterElements.isNotEmpty ||
      orderBefore != null ||
      selectionChanged;

  DrawState applyBackward(DrawState state) => _apply(state, forward: false);

  DrawState applyForward(DrawState state) => _apply(state, forward: true);

  DrawState _apply(DrawState state, {required bool forward}) {
    final currentElements = state.domain.document.elements;
    final currentById = {
      for (final element in currentElements) element.id: element,
    };

    final removedIds = forward
        ? beforeElements.keys.where((id) => !afterElements.containsKey(id))
        : afterElements.keys.where((id) => !beforeElements.containsKey(id));

    final targetElements = forward ? afterElements : beforeElements;
    final nextById = Map<String, ElementState>.from(currentById);

    for (final id in removedIds) {
      nextById.remove(id);
    }
    for (final entry in targetElements.entries) {
      nextById[entry.key] = entry.value;
    }

    final order = forward ? orderAfter : orderBefore;
    final targetOrder =
        order ?? currentElements.map((element) => element.id).toList();

    final nextElements = <ElementState>[];
    for (final id in targetOrder) {
      final element = nextById[id];
      if (element != null) {
        nextElements.add(element);
      }
    }

    if (order == null && nextElements.length != nextById.length) {
      final knownOrderIds = targetOrder.toSet();
      for (final id in nextById.keys) {
        if (!knownOrderIds.contains(id)) {
          final element = nextById[id];
          if (element != null) {
            nextElements.add(element);
          }
        }
      }
    }

    final selection = forward ? selectionAfter : selectionBefore;
    final resolvedElements = reindexZIndices
        ? _reindexElements(nextElements)
        : nextElements;

    return state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(elements: resolvedElements),
        selection: selection ?? state.domain.selection,
      ),
      application: state.application.copyWith(
        interaction: const IdleState(),
        selectionOverlay: SelectionOverlayState.empty,
      ),
    );
  }
}

void _collectChangedElementsById({
  required Map<String, ElementState> beforeById,
  required Map<String, ElementState> afterById,
  required Set<String> changedIds,
  required Map<String, ElementState> beforeElements,
  required Map<String, ElementState> afterElements,
}) {
  for (final id in changedIds) {
    final beforeElement = beforeById[id];
    final afterElement = afterById[id];

    if (beforeElement != null && afterElement != null) {
      if (beforeElement != afterElement) {
        beforeElements[id] = beforeElement;
        afterElements[id] = afterElement;
      }
      continue;
    }

    if (beforeElement != null) {
      beforeElements[id] = beforeElement;
    }
    if (afterElement != null) {
      afterElements[id] = afterElement;
    }
  }
}

List<ElementState> _reindexElements(List<ElementState> elements) {
  var changed = false;
  final reindexed = <ElementState>[];
  for (var index = 0; index < elements.length; index++) {
    final element = elements[index];
    if (element.zIndex == index) {
      reindexed.add(element);
      continue;
    }
    changed = true;
    reindexed.add(element.copyWith(zIndex: index));
  }
  return changed ? reindexed : elements;
}

SelectionState _copySelection(SelectionState selection) => SelectionState(
  selectedIds: Set<String>.from(selection.selectedIds),
  selectionVersion: selection.selectionVersion,
);
