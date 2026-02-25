import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_result.dart';
import 'package:snow_draw_engine/draw/edit/edit_operations.dart';
import 'package:snow_draw_engine/draw/edit/preview/edit_preview.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/application_state.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/edit_context.dart';
import 'package:snow_draw_engine/draw/types/edit_operation_id.dart';
import 'package:snow_draw_engine/draw/types/edit_transform.dart';
import 'package:test/test.dart';

void main() {
  test('build always produces a fresh DrawStateView for editing states', () {
    final operation = _CountingPreviewOperation();
    final registry = DefaultEditOperationRegistry.custom([operation]);
    final state = _editingState(operationId: operation.id);

    final builderA = DrawStateViewBuilder(editOperations: registry);
    final builderB = DrawStateViewBuilder(editOperations: registry);

    final viewA = builderA.build(state);
    final viewB = builderB.build(state);
    final viewAgain = builderA.build(state);

    expect(identical(viewA, viewB), isFalse);
    expect(identical(viewA, viewAgain), isFalse);
    expect(operation.buildPreviewCallCount, 3);
  });
}

DrawState _editingState({required EditOperationId operationId}) {
  const elementId = 'rect-1';
  const element = ElementState(
    id: elementId,
    rect: DrawRect(maxX: 100, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  final domain = DomainState(
    document: DocumentState(elements: const [element]),
    selection: const SelectionState(selectedIds: {elementId}),
  );
  final interaction = EditingState(
    operationId: operationId,
    sessionId: 'session-1',
    context: _TestEditContext(
      startPosition: DrawPoint.zero,
      startBounds: element.rect,
      selectedIdsAtStart: const {elementId},
      selectionVersion: domain.selection.selectionVersion,
      elementsVersion: domain.document.elementsVersion,
    ),
    currentTransform: MoveTransform.zero,
  );

  return DrawState(
    domain: domain,
    application: ApplicationState.initial().copyWith(interaction: interaction),
  );
}

final class _CountingPreviewOperation extends EditOperation {
  @override
  EditOperationId get id => 'counting-preview-op';

  var buildPreviewCallCount = 0;

  @override
  EditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) => _TestEditContext(
    startPosition: position,
    startBounds: DrawRect.fromPoint(position),
    selectedIdsAtStart: state.domain.selection.selectedIds,
    selectionVersion: state.domain.selection.selectionVersion,
    elementsVersion: state.domain.document.elementsVersion,
  );

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
  }) => EditUpdateResult<EditTransform>(transform: transform);

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => state;

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

final class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
  });
}
