import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../services/element_index_service.dart';
import '../../types/draw_point.dart';
import '../core/reducer_utils.dart';

DrawState handleDeleteElements(
  DrawState state,
  DeleteElements action,
  ElementReducerDeps _,
) {
  final deleteIds = action.elementIds.toSet();

  final updatedSerials = <String, ElementState>{};
  for (final element in state.domain.document.elements) {
    final data = element.data;
    if (data is! SerialNumberData) {
      continue;
    }
    final boundId = data.textElementId;
    if (boundId == null) {
      continue;
    }
    if (deleteIds.contains(element.id)) {
      deleteIds.add(boundId);
      continue;
    }
    if (deleteIds.contains(boundId)) {
      updatedSerials[element.id] = element.copyWith(
        data: data.copyWith(textElementId: null),
      );
    }
  }

  final newElements = <ElementState>[];
  for (final element in state.domain.document.elements) {
    if (deleteIds.contains(element.id)) {
      continue;
    }
    final updated = updatedSerials[element.id];
    newElements.add(updated ?? element);
  }

  final newSelectedIds = state.domain.selection.selectedIds
      .where((id) => !deleteIds.contains(id))
      .toSet();

  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: newElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}

DrawState handleDuplicateElements(
  DrawState state,
  DuplicateElements action,
  ElementReducerDeps context,
) {
  if (action.elementIds.isEmpty) {
    context.log.store.warning('Duplicate failed: empty selection', {
      'action': action.runtimeType.toString(),
    });
    context.eventBus?.emit(
      ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'No element ids provided',
      ),
    );
    return state;
  }

  final index = ElementIndexService(state.domain.document.elements);
  final idsToDuplicate = <String>{...action.elementIds};
  for (final id in action.elementIds) {
    final element = index[id];
    final data = element?.data;
    if (data is SerialNumberData) {
      final boundId = data.textElementId;
      if (boundId != null && index[boundId] != null) {
        idsToDuplicate.add(boundId);
      }
    }
  }

  final elementsToDuplicate = <ElementState>[];
  for (final element in state.domain.document.elements) {
    if (idsToDuplicate.contains(element.id)) {
      elementsToDuplicate.add(element);
    }
  }
  if (elementsToDuplicate.isEmpty) {
    context.log.store.warning('Duplicate failed: no elements found', {
      'action': action.runtimeType.toString(),
      'elementIds': action.elementIds.join(','),
    });
    context.eventBus?.emit(
      ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'No valid elements to duplicate',
        details: {'elementIds': action.elementIds.toList()},
      ),
    );
    return state;
  }

  final idMap = <String, String>{};
  for (final element in elementsToDuplicate) {
    idMap[element.id] = context.idGenerator();
  }

  final newElements = <ElementState>[];
  final newSelectedIds = <String>{};

  for (final element in elementsToDuplicate) {
    final newId = idMap[element.id]!;
    var nextData = element.data;
    if (nextData is SerialNumberData) {
      final mapped = nextData.textElementId == null
          ? null
          : idMap[nextData.textElementId!];
      nextData = nextData.copyWith(textElementId: mapped);
    }
    final duplicated = element.copyWith(
      id: newId,
      rect: element.rect.translate(
        DrawPoint(x: action.offsetX, y: action.offsetY),
      ),
      data: nextData,
    );
    newElements.add(duplicated);
    if (action.elementIds.contains(element.id)) {
      newSelectedIds.add(newId);
    }
  }

  final mergedElements = [...state.domain.document.elements, ...newElements];
  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: mergedElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}
