import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/filter_interaction_state_change.dart';

void main() {
  group('isFilterInteractionMutationOnly', () {
    test('returns true for filter create rect updates', () {
      final base = _baseState(elements: const [_filterElement]);
      final previous = _withInteraction(
        base,
        CreatingState(
          element: _filterElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
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
      const context = MoveEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 40, maxY: 40),
        selectedIdsAtStart: {'filter'},
        selectionVersion: 1,
        elementsVersion: 1,
        elementSnapshots: {},
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
      const context = MoveEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'filter', 'rect'},
        selectionVersion: 1,
        elementsVersion: 1,
        elementSnapshots: {},
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
