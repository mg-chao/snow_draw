import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  test('draw action runtime type names stay stable', () {
    final samples = <_ActionTypeSample>[
      _ActionTypeSample(
        action: const SelectElement(
          elementId: 'element-1',
          position: DrawPoint.zero,
        ),
        expectedTypeName: 'SelectElement',
      ),
      _ActionTypeSample(
        action: const ClearSelection(),
        expectedTypeName: 'ClearSelection',
      ),
      _ActionTypeSample(
        action: const SelectAll(),
        expectedTypeName: 'SelectAll',
      ),
      _ActionTypeSample(
        action: const CreateElement(
          typeId: ElementTypeId<ElementData>('compatibility_test'),
          position: DrawPoint.zero,
        ),
        expectedTypeName: 'CreateElement',
      ),
      _ActionTypeSample(
        action: UpdateCreatingElement(positions: const [DrawPoint.zero]),
        expectedTypeName: 'UpdateCreatingElement',
      ),
      _ActionTypeSample(
        action: const AddArrowPoint(position: DrawPoint.zero),
        expectedTypeName: 'AddArrowPoint',
      ),
      _ActionTypeSample(
        action: const FinishCreateElement(),
        expectedTypeName: 'FinishCreateElement',
      ),
      _ActionTypeSample(
        action: const CancelCreateElement(),
        expectedTypeName: 'CancelCreateElement',
      ),
      _ActionTypeSample(
        action: DeleteElements(elementIds: const ['element-1']),
        expectedTypeName: 'DeleteElements',
      ),
      _ActionTypeSample(
        action: DuplicateElements(elementIds: const ['element-1']),
        expectedTypeName: 'DuplicateElements',
      ),
      _ActionTypeSample(
        action: const ChangeElementZIndex(
          elementId: 'element-1',
          operation: ZIndexOperation.bringToFront,
        ),
        expectedTypeName: 'ChangeElementZIndex',
      ),
      _ActionTypeSample(
        action: ChangeElementsZIndex(
          elementIds: const ['element-1'],
          operation: ZIndexOperation.bringForward,
        ),
        expectedTypeName: 'ChangeElementsZIndex',
      ),
      _ActionTypeSample(
        action: UpdateElementsStyle(
          elementIds: const ['element-1'],
          opacity: 0.5,
        ),
        expectedTypeName: 'UpdateElementsStyle',
      ),
      _ActionTypeSample(
        action: const UpdateGlobalElements(),
        expectedTypeName: 'UpdateGlobalElements',
      ),
      _ActionTypeSample(
        action: CreateSerialNumberTextElements(elementIds: const ['element-1']),
        expectedTypeName: 'CreateSerialNumberTextElements',
      ),
      _ActionTypeSample(
        action: const StartTextEdit(position: DrawPoint.zero),
        expectedTypeName: 'StartTextEdit',
      ),
      _ActionTypeSample(
        action: const UpdateTextEdit(text: 'draft'),
        expectedTypeName: 'UpdateTextEdit',
      ),
      _ActionTypeSample(
        action: const RefreshAutoResizeTextLayoutsAfterFontLoad(),
        expectedTypeName: 'RefreshAutoResizeTextLayoutsAfterFontLoad',
      ),
      _ActionTypeSample(
        action: const FinishTextEdit(
          elementId: 'element-1',
          text: 'text',
          isNew: false,
        ),
        expectedTypeName: 'FinishTextEdit',
      ),
      _ActionTypeSample(
        action: const CancelTextEdit(),
        expectedTypeName: 'CancelTextEdit',
      ),
      _ActionTypeSample(
        action: const StartEdit(
          operationId: EditOperationIds.move,
          position: DrawPoint.zero,
          params: MoveOperationParams(),
        ),
        expectedTypeName: 'StartEdit',
      ),
      _ActionTypeSample(
        action: const UpdateEdit(currentPosition: DrawPoint.zero),
        expectedTypeName: 'UpdateEdit',
      ),
      _ActionTypeSample(
        action: const FinishEdit(),
        expectedTypeName: 'FinishEdit',
      ),
      _ActionTypeSample(
        action: const CancelEdit(),
        expectedTypeName: 'CancelEdit',
      ),
      _ActionTypeSample(
        action: const SetDragPending(
          pointerDownPosition: DrawPoint.zero,
          intent: PendingMoveIntent(),
        ),
        expectedTypeName: 'SetDragPending',
      ),
      _ActionTypeSample(
        action: const ClearDragPending(),
        expectedTypeName: 'ClearDragPending',
      ),
      _ActionTypeSample(
        action: const StartBoxSelect(startPosition: DrawPoint.zero),
        expectedTypeName: 'StartBoxSelect',
      ),
      _ActionTypeSample(
        action: const UpdateBoxSelect(currentPosition: DrawPoint.zero),
        expectedTypeName: 'UpdateBoxSelect',
      ),
      _ActionTypeSample(
        action: const FinishBoxSelect(),
        expectedTypeName: 'FinishBoxSelect',
      ),
      _ActionTypeSample(
        action: const CancelBoxSelect(),
        expectedTypeName: 'CancelBoxSelect',
      ),
      _ActionTypeSample(
        action: const MoveCamera(dx: 1, dy: -1),
        expectedTypeName: 'MoveCamera',
      ),
      _ActionTypeSample(
        action: const ZoomCamera(scale: 1.25),
        expectedTypeName: 'ZoomCamera',
      ),
      _ActionTypeSample(action: const Undo(), expectedTypeName: 'Undo'),
      _ActionTypeSample(action: const Redo(), expectedTypeName: 'Redo'),
      _ActionTypeSample(
        action: const ClearHistory(),
        expectedTypeName: 'ClearHistory',
      ),
    ];

    for (final sample in samples) {
      expect(sample.action.runtimeType.toString(), sample.expectedTypeName);
    }
  });
}

class _ActionTypeSample {
  const _ActionTypeSample({
    required this.action,
    required this.expectedTypeName,
  });

  final DrawAction action;
  final String expectedTypeName;
}
