import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
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
import 'package:snow_draw_core/ui/canvas/serial_number_interaction_state_change.dart';

void main() {
  group('isSerialNumberInteractionMutationOnly', () {
    test('returns true for serial-number creation rect updates', () {
      final base = _baseState(elements: const [_serialElement]);
      final previous = _withInteraction(
        base,
        CreatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 12, minY: 12, maxX: 48, maxY: 48),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 16, minY: 16, maxX: 52, maxY: 52),
        ),
      );

      expect(
        isSerialNumberInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns true for serial-number edit transform updates', () {
      final base = _baseState(
        elements: const [_serialElement],
        selectedIds: const {'serial'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 12, minY: 12, maxX: 48, maxY: 48),
        selectedIdsAtStart: {'serial'},
        selectionVersion: 1,
        elementsVersion: 1,
      );
      final previous = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'serial_edit',
          context: context,
          currentTransform: MoveTransform.zero,
        ),
      );
      final next = _withInteraction(
        base,
        const EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'serial_edit',
          context: context,
          currentTransform: MoveTransform(dx: 6, dy: 4),
        ),
      );

      expect(
        isSerialNumberInteractionMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false when domain changes', () {
      final base = _baseState(elements: const [_serialElement]);
      final previous = _withInteraction(
        base,
        CreatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 12, minY: 12, maxX: 48, maxY: 48),
        ),
      );
      final next = _withInteraction(
        base,
        CreatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 20, y: 20),
          currentRect: const DrawRect(minX: 16, minY: 16, maxX: 52, maxY: 52),
        ),
      ).copyWith(domain: previous.domain.withSelected('serial'));

      expect(
        isSerialNumberInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false for non-serial editing sessions', () {
      const rectangle = ElementState(
        id: 'rect',
        rect: DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final base = _baseState(
        elements: const [rectangle],
        selectedIds: const {'rect'},
      );
      const context = _TestEditContext(
        startPosition: DrawPoint(x: 20, y: 20),
        startBounds: DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
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
          currentTransform: MoveTransform(dx: 4, dy: 2),
        ),
      );

      expect(
        isSerialNumberInteractionMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

const _serialElement = ElementState(
  id: 'serial',
  rect: DrawRect(minX: 12, minY: 12, maxX: 48, maxY: 48),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: SerialNumberData(),
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
