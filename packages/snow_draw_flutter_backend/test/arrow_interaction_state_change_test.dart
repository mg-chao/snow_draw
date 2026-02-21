import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/arrow_interaction_state_change.dart';

void main() {
  group('isArrowInteractionMutationOnly', () {
    test('returns true for arrow create rect updates', () {
      final base = _baseState(elements: const []);
      final previous = _creatingState(
        base: base,
        element: _arrowElement,
        currentRect: _collapsedRect,
      );
      final next = _creatingState(
        base: base,
        element: _arrowElement,
        currentRect: _expandedRect,
      );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for arrow edit transform updates', () {
      final base = _baseState(
        elements: const [_arrowElement],
        selectedIds: const {'arrow'},
      );
      final previous = _editingState(
        base: base,
        sessionId: 'arrow_edit',
        context: _arrowEditContext,
        transform: MoveTransform.zero,
      );
      final next = _editingState(
        base: base,
        sessionId: 'arrow_edit',
        context: _arrowEditContext,
        transform: const MoveTransform(dx: 8, dy: 6),
      );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false for mixed non-arrow edit context', () {
      final base = _baseState(
        elements: const [_arrowElement, _rectangleElement],
        selectedIds: const {'arrow', 'rect'},
      );
      final previous = _editingState(
        base: base,
        sessionId: 'mixed_edit',
        context: _mixedEditContext,
        transform: MoveTransform.zero,
      );
      final next = _editingState(
        base: base,
        sessionId: 'mixed_edit',
        context: _mixedEditContext,
        transform: const MoveTransform(dx: 4, dy: 4),
      );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when interaction is not arrow-based', () {
      final base = _baseState(elements: const [_rectangleElement]);
      final previous = _creatingState(
        base: base,
        element: _rectangleElement,
        currentRect: _collapsedRect,
      );
      final next = _creatingState(
        base: base,
        element: _rectangleElement,
        currentRect: _expandedRect,
      );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when domain changes', () {
      final base = _baseState(
        elements: const [_arrowElement],
        selectedIds: const {'arrow'},
      );
      final previous = _editingState(
        base: base,
        sessionId: 'arrow_edit',
        context: _arrowEditContext,
        transform: MoveTransform.zero,
      );
      final next =
          _editingState(
            base: base,
            sessionId: 'arrow_edit',
            context: _arrowEditContext,
            transform: const MoveTransform(dx: 8, dy: 4),
          ).copyWith(
            domain: DomainState(
              document: DocumentState(elements: const [_arrowElement]),
              selection: const SelectionState(selectedIds: {'arrow'}),
            ),
          );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

const _arrowElement = ElementState(
  id: 'arrow',
  rect: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: ArrowData(),
);

const _rectangleElement = ElementState(
  id: 'rect',
  rect: DrawRect(minX: 130, minY: 20, maxX: 220, maxY: 70),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: RectangleData(),
);

const _startPosition = DrawPoint(x: 20, y: 20);
const _collapsedRect = DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20);
const _expandedRect = DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 70);

const _arrowEditContext = MoveEditContext(
  startPosition: _startPosition,
  startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
  selectedIdsAtStart: {'arrow'},
  selectionVersion: 1,
  elementsVersion: 1,
  elementSnapshots: {},
);

const _mixedEditContext = MoveEditContext(
  startPosition: _startPosition,
  startBounds: DrawRect(minX: 10, minY: 10, maxX: 150, maxY: 90),
  selectedIdsAtStart: {'arrow', 'rect'},
  selectionVersion: 1,
  elementsVersion: 1,
  elementSnapshots: {},
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

DrawState _creatingState({
  required DrawState base,
  required ElementState element,
  required DrawRect currentRect,
}) => _withInteraction(
  base,
  CreatingState(
    element: element,
    startPosition: _startPosition,
    currentRect: currentRect,
  ),
);

DrawState _editingState({
  required DrawState base,
  required String sessionId,
  required EditContext context,
  required EditTransform transform,
}) => _withInteraction(
  base,
  EditingState(
    operationId: EditOperationIds.move,
    sessionId: sessionId,
    context: context,
    currentTransform: transform,
  ),
);
