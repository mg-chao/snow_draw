import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/ui/canvas/filter_interaction_state_change.dart';

void main() {
  group('isFilterInteractionMutationOnly', () {
    test('returns true for filter create rect updates', () {
      final base = _baseState(elements: const [_filterElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _filterElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _filterElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 64, maxY: 54),
        ),
      );

      expect(
        isFilterInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for filter edit transform updates', () {
      final base = _baseState(
        elements: const [_filterElement],
        selectedIds: const {'filter'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 40, maxY: 40),
        selectedIdsAtStart: {'filter'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'filter_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'filter_edit',
          context: context,
          currentTransform: MoveTransform(dx: 5, dy: -3),
        ),
      );

      expect(
        isFilterInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false for mixed non-filter edit context', () {
      final base = _baseState(
        elements: const [_filterElement, _rectangleElement],
        selectedIds: const {'filter', 'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'filter', 'rect'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'mixed_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'mixed_edit',
          context: context,
          currentTransform: MoveTransform(dx: 8, dy: 4),
        ),
      );

      expect(
        isFilterInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

CreatingState _creatingState({
  required ElementState element,
  required DrawPoint startPosition,
  required DrawRect currentRect,
  CreationMode creationMode = const RectCreationMode(),
}) => CreatingState(
  element: element,
  startPosition: startPosition,
  currentRect: currentRect,
  creationMode: creationMode,
);

const _filterElement = ElementState(
  id: 'filter',
  rect: DrawRect(minX: 10, minY: 10, maxX: 40, maxY: 40),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: FilterData(),
);

const _rectangleElement = ElementState(
  id: 'rect',
  rect: DrawRect(minX: 50, minY: 50, maxX: 90, maxY: 90),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: RectangleData(),
);

DrawState _baseState({
  required List<ElementState> elements,
  Set<String> selectedIds = const <String>{},
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

DrawState _withInteraction(DrawState base, InteractionState interaction) => base
    .copyWith(application: base.application.copyWith(interaction: interaction));

class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
  });
}
