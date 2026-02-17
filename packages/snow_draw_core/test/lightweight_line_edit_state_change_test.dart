import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
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
import 'package:snow_draw_core/draw/types/snap_guides.dart';
import 'package:snow_draw_core/ui/canvas/lightweight_line_edit_state_change.dart';

void main() {
  group('isLightweightLineInteractionMutationOnly', () {
    test('returns true for line creation updates', () {
      final base = _baseState(elements: const [_lineElement]);
      const creatingElement = ElementState(
        id: 'draft-line',
        rect: DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: LineData(),
      );
      final previous = _withInteraction(
        base,
        CreatingState(
          element: creatingElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
          creationMode: const PointCreationMode(
            fixedPoints: [DrawPoint(x: 20, y: 20)],
            currentPoint: DrawPoint(x: 20, y: 20),
          ),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: creatingElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 60),
          creationMode: const PointCreationMode(
            fixedPoints: [DrawPoint(x: 20, y: 20)],
            currentPoint: DrawPoint(x: 80, y: 60),
          ),
        ),
      );

      expect(
        isLightweightLineInteractionMutationOnly(
          previous: previous,
          next: next,
        ),
        isTrue,
      );
    });

    test('returns false for non-line creation updates', () {
      final base = _baseState(elements: const [_rectangleElement]);
      const creatingElement = ElementState(
        id: 'draft-rect',
        rect: DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: RectangleData(),
      );
      final previous = _withInteraction(
        base,
        CreatingState(
          element: creatingElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 20, maxY: 20),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: creatingElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 60),
        ),
      );

      expect(
        isLightweightLineInteractionMutationOnly(
          previous: previous,
          next: next,
        ),
        isFalse,
      );
    });

    test('returns true for lightweight line edit updates', () {
      final base = _baseState(
        elements: const [_lineElement],
        selectedIds: const {'line'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'line'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform(dx: 6, dy: 4),
        ),
      );

      expect(
        isLightweightLineInteractionMutationOnly(
          previous: previous,
          next: next,
        ),
        isTrue,
      );
    });

    test('returns false for mixed non-line edit updates', () {
      final base = _baseState(
        elements: const [_freeDrawElement, _rectangleElement],
        selectedIds: const {'free', 'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
        selectedIdsAtStart: {'free', 'rect'},
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
        isLightweightLineInteractionMutationOnly(
          previous: previous,
          next: next,
        ),
        isFalse,
      );
    });
  });

  group('isLightweightLineEditMutationOnly', () {
    test('returns true for free-draw edit transform updates', () {
      final base = _baseState(
        elements: const [_freeDrawElement],
        selectedIds: const {'free'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'free'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'free_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'free_edit',
          context: context,
          currentTransform: MoveTransform(dx: 8, dy: 6),
        ),
      );

      expect(
        isLightweightLineEditMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for line snap-guide-only updates', () {
      final base = _baseState(
        elements: const [_lineElement],
        selectedIds: const {'line'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'line'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform.zero,
          snapGuides: [
            SnapGuide(
              kind: SnapGuideKind.point,
              axis: SnapGuideAxis.horizontal,
              start: DrawPoint(x: 0, y: 10),
              end: DrawPoint(x: 100, y: 10),
            ),
          ],
        ),
      );

      expect(
        isLightweightLineEditMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false when selected context contains non-line elements', () {
      final base = _baseState(
        elements: const [_freeDrawElement, _rectangleElement],
        selectedIds: const {'free', 'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
        selectedIdsAtStart: {'free', 'rect'},
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
        isLightweightLineEditMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when domain changes', () {
      final base = _baseState(
        elements: const [_lineElement],
        selectedIds: const {'line'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
        selectedIdsAtStart: {'line'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'line_edit',
          context: context,
          currentTransform: MoveTransform(dx: 8, dy: 4),
        ),
      ).copyWith(domain: previous.domain.withSelected('line'));

      expect(
        isLightweightLineEditMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

const _freeDrawElement = ElementState(
  id: 'free',
  rect: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: FreeDrawData(),
);

const _lineElement = ElementState(
  id: 'line',
  rect: DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: LineData(),
);

const _rectangleElement = ElementState(
  id: 'rect',
  rect: DrawRect(minX: 30, minY: 30, maxX: 110, maxY: 110),
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
