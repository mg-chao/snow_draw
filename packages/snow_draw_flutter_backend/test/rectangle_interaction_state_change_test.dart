import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
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
import 'package:snow_draw_flutter_backend/ui/canvas/rectangle_interaction_state_change.dart';

void main() {
  group('isRectangleInteractionMutationOnly', () {
    test('returns true for rectangle create rect updates', () {
      final base = _baseState(elements: const []);
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
        isRectangleInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for rectangle edit transform updates', () {
      final base = _baseState(
        elements: const [_rectangleElement],
        selectedIds: const {'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
        selectedIdsAtStart: {'rect'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'rect_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'rect_edit',
          context: context,
          currentTransform: MoveTransform(dx: 8, dy: 6),
        ),
      );

      expect(
        isRectangleInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test(
      'returns false when selected context contains non-rectangle elements',
      () {
        final base = _baseState(
          elements: const [_rectangleElement, _arrowElement],
          selectedIds: const {'rect', 'arrow'},
        );
        const context = _TestEditContext(
          startPosition: DrawPoint(x: 20, y: 20),
          startBounds: DrawRect(minX: 10, minY: 10, maxX: 140, maxY: 90),
          selectedIdsAtStart: {'rect', 'arrow'},
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
          isRectangleInteractionMutationOnly(previous: previous, next: next),
          isFalse,
        );
      },
    );

    test('returns false when rectangle has bound arrows', () {
      final boundArrow = _arrowElement.copyWith(
        data: const ArrowData(
          startBinding: ArrowBinding(
            elementId: 'rect',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
        ),
      );
      final base = _baseState(
        elements: [_rectangleElement, boundArrow],
        selectedIds: const {'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
        selectedIdsAtStart: {'rect'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'rect_edit_bound',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'rect_edit_bound',
          context: context,
          currentTransform: MoveTransform(dx: 6, dy: 5),
        ),
      );

      expect(
        isRectangleInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when domain changes', () {
      final base = _baseState(
        elements: const [_rectangleElement],
        selectedIds: const {'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
        selectedIdsAtStart: {'rect'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'rect_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next =
          _withInteraction(
            base,
            const EditingState(
              operationId: EditOperationIds.move,
              sessionId: 'rect_edit',
              context: context,
              currentTransform: MoveTransform(dx: 8, dy: 4),
            ),
          ).copyWith(
            domain: DomainState(
              document: DocumentState(elements: const [_rectangleElement]),
              selection: const SelectionState(selectedIds: {'rect'}),
            ),
          );

      expect(
        isRectangleInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

const _rectangleElement = ElementState(
  id: 'rect',
  rect: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

const _arrowElement = ElementState(
  id: 'arrow',
  rect: DrawRect(minX: 130, minY: 20, maxX: 220, maxY: 70),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: ArrowData(),
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
