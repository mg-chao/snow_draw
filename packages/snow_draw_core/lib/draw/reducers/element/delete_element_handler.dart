import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
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
  final newElements = state.domain.document.elements
      .where((element) => !action.elementIds.contains(element.id))
      .toList();

  final newSelectedIds = state.domain.selection.selectedIds
      .where((id) => !action.elementIds.contains(id))
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

  final elementsToDuplicate = <ElementState>[];
  final index = ElementIndexService(state.domain.document.elements);
  for (final id in action.elementIds) {
    final element = index[id];
    if (element != null) {
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

  final newElements = <ElementState>[];
  final newSelectedIds = <String>{};

  for (final element in elementsToDuplicate) {
    final duplicated = element.copyWith(
      id: context.idGenerator(),
      rect: element.rect.translate(
        DrawPoint(x: action.offsetX, y: action.offsetY),
      ),
    );
    newElements.add(duplicated);
    newSelectedIds.add(duplicated.id);
  }

  final mergedElements = [...state.domain.document.elements, ...newElements];
  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: mergedElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}
