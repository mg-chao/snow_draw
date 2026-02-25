import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  test('draw action runtime type names stay stable', () {
    final samples = <_ActionTypeSample>[
      const _ActionTypeSample(
        action: SelectElement(elementId: 'element-1', position: DrawPoint.zero),
        expectedTypeName: 'SelectElement',
      ),
      const _ActionTypeSample(
        action: ClearSelection(),
        expectedTypeName: 'ClearSelection',
      ),
      const _ActionTypeSample(
        action: SelectAll(),
        expectedTypeName: 'SelectAll',
      ),
      const _ActionTypeSample(
        action: CreateElement(
          typeId: ElementTypeId<ElementData>('compatibility_test'),
          position: DrawPoint.zero,
        ),
        expectedTypeName: 'CreateElement',
      ),
      _ActionTypeSample(
        action: UpdateCreatingElement(positions: const [DrawPoint.zero]),
        expectedTypeName: 'UpdateCreatingElement',
      ),
      const _ActionTypeSample(
        action: AddArrowPoint(position: DrawPoint.zero),
        expectedTypeName: 'AddArrowPoint',
      ),
      const _ActionTypeSample(
        action: FinishCreateElement(),
        expectedTypeName: 'FinishCreateElement',
      ),
      const _ActionTypeSample(
        action: CancelCreateElement(),
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
      const _ActionTypeSample(
        action: ChangeElementZIndex(
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
      const _ActionTypeSample(
        action: UpdateGlobalElements(),
        expectedTypeName: 'UpdateGlobalElements',
      ),
      _ActionTypeSample(
        action: CreateSerialNumberTextElements(elementIds: const ['element-1']),
        expectedTypeName: 'CreateSerialNumberTextElements',
      ),
      const _ActionTypeSample(
        action: StartTextEdit(position: DrawPoint.zero),
        expectedTypeName: 'StartTextEdit',
      ),
      const _ActionTypeSample(
        action: UpdateTextEdit(text: 'draft'),
        expectedTypeName: 'UpdateTextEdit',
      ),
      const _ActionTypeSample(
        action: RefreshAutoResizeTextLayoutsAfterFontLoad(),
        expectedTypeName: 'RefreshAutoResizeTextLayoutsAfterFontLoad',
      ),
      const _ActionTypeSample(
        action: FinishTextEdit(
          elementId: 'element-1',
          text: 'text',
          isNew: false,
        ),
        expectedTypeName: 'FinishTextEdit',
      ),
      const _ActionTypeSample(
        action: CancelTextEdit(),
        expectedTypeName: 'CancelTextEdit',
      ),
      const _ActionTypeSample(
        action: StartEdit(
          operationId: EditOperationIds.move,
          position: DrawPoint.zero,
          params: MoveOperationParams(),
        ),
        expectedTypeName: 'StartEdit',
      ),
      const _ActionTypeSample(
        action: UpdateEdit(currentPosition: DrawPoint.zero),
        expectedTypeName: 'UpdateEdit',
      ),
      const _ActionTypeSample(
        action: FinishEdit(),
        expectedTypeName: 'FinishEdit',
      ),
      const _ActionTypeSample(
        action: CancelEdit(),
        expectedTypeName: 'CancelEdit',
      ),
      const _ActionTypeSample(
        action: SetDragPending(
          pointerDownPosition: DrawPoint.zero,
          intent: PendingMoveIntent(),
        ),
        expectedTypeName: 'SetDragPending',
      ),
      const _ActionTypeSample(
        action: ClearDragPending(),
        expectedTypeName: 'ClearDragPending',
      ),
      const _ActionTypeSample(
        action: StartBoxSelect(startPosition: DrawPoint.zero),
        expectedTypeName: 'StartBoxSelect',
      ),
      const _ActionTypeSample(
        action: UpdateBoxSelect(currentPosition: DrawPoint.zero),
        expectedTypeName: 'UpdateBoxSelect',
      ),
      const _ActionTypeSample(
        action: FinishBoxSelect(),
        expectedTypeName: 'FinishBoxSelect',
      ),
      const _ActionTypeSample(
        action: CancelBoxSelect(),
        expectedTypeName: 'CancelBoxSelect',
      ),
      const _ActionTypeSample(
        action: MoveCamera(dx: 1, dy: -1),
        expectedTypeName: 'MoveCamera',
      ),
      const _ActionTypeSample(
        action: ZoomCamera(scale: 1.25),
        expectedTypeName: 'ZoomCamera',
      ),
      const _ActionTypeSample(action: Undo(), expectedTypeName: 'Undo'),
      const _ActionTypeSample(action: Redo(), expectedTypeName: 'Redo'),
      const _ActionTypeSample(
        action: ClearHistory(),
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
