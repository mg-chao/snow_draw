import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
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
import 'package:snow_draw_core/ui/canvas/arrow_interaction_state_change.dart';

void main() {
  group('isArrowInteractionMutationOnly', () {
    test('returns true for arrow create rect updates', () {
      final base = _baseState(elements: const []);
      final previous = _withInteraction(
        base,
        CreatingState(
          element: _arrowElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: _arrowElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 70),
        ),
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
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
        selectedIdsAtStart: {'arrow'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'arrow_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'arrow_edit',
          context: context,
          currentTransform: MoveTransform(dx: 8, dy: 6),
        ),
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
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 150, maxY: 90),
        selectedIdsAtStart: {'arrow', 'rect'},
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
          currentTransform: MoveTransform(dx: 4, dy: 4),
        ),
      );

      expect(
        isArrowInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when interaction is not arrow-based', () {
      final base = _baseState(elements: const [_rectangleElement]);
      final previous = _withInteraction(
        base,
        CreatingState(
          element: _rectangleElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: _rectangleElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 70),
        ),
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
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
        selectedIdsAtStart: {'arrow'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'arrow_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next =
          _withInteraction(
            base,
            const EditingState(
              operationId: EditOperationIds.move,
              sessionId: 'arrow_edit',
              context: context,
              currentTransform: MoveTransform(dx: 8, dy: 4),
            ),
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
