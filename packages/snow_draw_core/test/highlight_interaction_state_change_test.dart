import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
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
import 'package:snow_draw_core/ui/canvas/highlight_interaction_state_change.dart';

void main() {
  group('isHighlightInteractionMutationOnly', () {
    test('returns true for highlight create rect updates', () {
      final base = _baseState(elements: const []);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _highlightElement,
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _highlightElement,
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 70),
        ),
      );

      expect(
        isHighlightInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for highlight edit transform updates', () {
      final base = _baseState(
        elements: const [_highlightElement],
        selectedIds: const {'highlight'},
      );
      final previous = _withInteraction(
        base,
        _moveEditingState(
          sessionId: 'highlight_edit',
          context: _highlightEditContext,
          transform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        _moveEditingState(
          sessionId: 'highlight_edit',
          context: _highlightEditContext,
          transform: const MoveTransform(dx: 8, dy: 6),
        ),
      );

      expect(
        isHighlightInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false for mixed highlight/non-highlight edit context', () {
      final base = _baseState(
        elements: const [_highlightElement, _rectangleElement],
        selectedIds: const {'highlight', 'rect'},
      );
      final previous = _withInteraction(
        base,
        _moveEditingState(
          sessionId: 'mixed_edit',
          context: _mixedEditContext,
          transform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        _moveEditingState(
          sessionId: 'mixed_edit',
          context: _mixedEditContext,
          transform: const MoveTransform(dx: 4, dy: 4),
        ),
      );

      expect(
        isHighlightInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when domain changes', () {
      final base = _baseState(
        elements: const [_highlightElement],
        selectedIds: const {'highlight'},
      );
      final previous = _withInteraction(
        base,
        _moveEditingState(
          sessionId: 'highlight_edit',
          context: _highlightEditContext,
          transform: MoveTransform.zero,
        ),
      );
      final next =
          _withInteraction(
            base,
            _moveEditingState(
              sessionId: 'highlight_edit',
              context: _highlightEditContext,
              transform: const MoveTransform(dx: 8, dy: 4),
            ),
          ).copyWith(
            domain: DomainState(
              document: DocumentState(elements: const [_highlightElement]),
              selection: const SelectionState(selectedIds: {'highlight'}),
            ),
          );

      expect(
        isHighlightInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false for non-highlight create sessions', () {
      final base = _baseState(elements: const []);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _rectangleElement,
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _rectangleElement,
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 70),
        ),
      );

      expect(
        isHighlightInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

const _highlightElement = ElementState(
  id: 'highlight',
  rect: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: HighlightData(),
);

const _rectangleElement = ElementState(
  id: 'rect',
  rect: DrawRect(minX: 130, minY: 20, maxX: 220, maxY: 70),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: RectangleData(),
);

const _highlightEditContext = MoveEditContext(
  startPosition: DrawPoint(x: 20, y: 20),
  startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 80),
  selectedIdsAtStart: {'highlight'},
  selectionVersion: 1,
  elementsVersion: 1,
  elementSnapshots: {},
);

const _mixedEditContext = MoveEditContext(
  startPosition: DrawPoint(x: 20, y: 20),
  startBounds: DrawRect(minX: 10, minY: 10, maxX: 140, maxY: 90),
  selectedIdsAtStart: {'highlight', 'rect'},
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

CreatingState _creatingState({
  required ElementState element,
  required DrawRect currentRect,
}) => CreatingState(
  element: element,
  startPosition: const DrawPoint(x: 20, y: 20),
  currentRect: currentRect,
);

EditingState _moveEditingState({
  required String sessionId,
  required EditContext context,
  required MoveTransform transform,
}) => EditingState(
  operationId: EditOperationIds.move,
  sessionId: sessionId,
  context: context,
  currentTransform: transform,
);
