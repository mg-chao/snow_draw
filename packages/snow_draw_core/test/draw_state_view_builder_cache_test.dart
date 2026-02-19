import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/core/edit_result.dart';
import 'package:snow_draw_core/draw/edit/edit_operation_registry_interface.dart';
import 'package:snow_draw_core/draw/edit/preview/edit_preview.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';

void main() {
  test(
    'reuses cached DrawStateView across builder instances for the same state',
    () {
      final operation = _CountingPreviewOperation();
      final registry = _SingleOperationRegistry(operation);
      final state = _editingState(operationId: operation.id);

      final builderA = DrawStateViewBuilder(editOperations: registry);
      final builderB = DrawStateViewBuilder(editOperations: registry);

      final viewA = builderA.build(state);
      final viewB = builderB.build(state);
      final viewAgain = builderA.build(state);

      expect(identical(viewA, viewB), isTrue);
      expect(identical(viewA, viewAgain), isTrue);
      expect(operation.buildPreviewCallCount, 1);
    },
  );
}

DrawState _editingState({required EditOperationId operationId}) {
  const element = ElementState(
    id: 'rect-1',
    rect: DrawRect(maxX: 100, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [element]),
      selection: const SelectionState(selectedIds: {'rect-1'}),
    ),
    application: ApplicationState.initial(),
  );

  final context = _TestEditContext(
    startBounds: element.rect,
    selectedIdsAtStart: const {'rect-1'},
    selectionVersion: base.domain.selection.selectionVersion,
    elementsVersion: base.domain.document.elementsVersion,
  );

  return base.copyWith(
    application: base.application.copyWith(
      interaction: EditingState(
        operationId: operationId,
        sessionId: 'session-1',
        context: context,
        currentTransform: MoveTransform.zero,
      ),
    ),
  );
}

class _SingleOperationRegistry implements EditOperationRegistry {
  _SingleOperationRegistry(this.operation);

  final EditOperation operation;

  @override
  Iterable<EditOperation> get allOperations => [operation];

  @override
  Iterable<EditOperationId> get allOperationIds => [operation.id];

  @override
  EditOperation? getOperation(EditOperationId operationId) =>
      operationId == operation.id ? operation : null;
}

class _CountingPreviewOperation extends EditOperation {
  @override
  EditOperationId get id => 'counting-preview-op';

  var buildPreviewCallCount = 0;

  @override
  EditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) => throw UnimplementedError();

  @override
  EditTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) => MoveTransform.zero;

  @override
  EditUpdateResult<EditTransform> update({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
    required DrawConfig config,
  }) => throw UnimplementedError();

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => state;

  @override
  DrawState cancel({required DrawState state, required EditContext context}) =>
      state;

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    buildPreviewCallCount += 1;
    return EditPreview.none;
  }
}

class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
  }) : super(startPosition: DrawPoint.zero);
}
