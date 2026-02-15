import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/core/edit_result.dart';
import 'package:snow_draw_core/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_core/draw/edit/edit_operation_registry_interface.dart';
import 'package:snow_draw_core/draw/edit/edit_operations.dart';
import 'package:snow_draw_core/draw/edit/move/move_operation.dart';
import 'package:snow_draw_core/draw/edit/preview/edit_preview.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
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

void main() {
  group('EditSessionService update no-op optimization', () {
    test('move no-op update reuses the existing draw state instance', () {
      final service = EditSessionService(
        editOperations: DefaultEditOperationRegistry.custom([
          const MoveOperation(),
        ]),
        configProvider: () => DrawConfig.defaultConfig,
      );
      final initial = _selectedRectangleState();
      const startPosition = DrawPoint(x: 50, y: 50);

      final started = service.start(
        state: initial,
        operationId: EditOperationIds.move,
        position: startPosition,
        params: const MoveOperationParams(),
        sessionId: 'session-1',
      );
      expect(started.failureReason, isNull);
      final editingState = started.state;

      final updated = service.update(
        state: editingState,
        currentPosition: startPosition,
      );

      expect(updated.failureReason, isNull);
      expect(updated.state, same(editingState));
    });

    test('guide changes still produce a new editing state', () {
      final operation = _GuideOnlyOperation();
      final service = EditSessionService(
        editOperations: _SingleOperationRegistry(operation),
        configProvider: () => DrawConfig.defaultConfig,
      );
      final initial = _selectedRectangleState();

      final started = service.start(
        state: initial,
        operationId: operation.id,
        position: DrawPoint.zero,
        params: const _GuideOnlyParams(),
        sessionId: 'session-2',
      );
      expect(started.failureReason, isNull);

      final beforeGuides = started.state;
      final withGuides = service.update(
        state: beforeGuides,
        currentPosition: const DrawPoint(x: 1, y: 0),
      );
      expect(withGuides.failureReason, isNull);
      expect(withGuides.state, isNot(same(beforeGuides)));

      final interactionWithGuides =
          withGuides.state.application.interaction as EditingState;
      expect(interactionWithGuides.snapGuides.length, 1);
    });

    test(
      'value-equal guides and transform skip rebuild on repeated updates',
      () {
        final operation = _GuideOnlyOperation();
        final service = EditSessionService(
          editOperations: _SingleOperationRegistry(operation),
          configProvider: () => DrawConfig.defaultConfig,
        );
        final initial = _selectedRectangleState();

        final started = service.start(
          state: initial,
          operationId: operation.id,
          position: DrawPoint.zero,
          params: const _GuideOnlyParams(),
          sessionId: 'session-3',
        );
        expect(started.failureReason, isNull);

        final firstUpdate = service.update(
          state: started.state,
          currentPosition: const DrawPoint(x: 1, y: 0),
        );
        expect(firstUpdate.failureReason, isNull);

        final secondUpdate = service.update(
          state: firstUpdate.state,
          currentPosition: const DrawPoint(x: 2, y: 0),
        );
        expect(secondUpdate.failureReason, isNull);
        expect(secondUpdate.state, same(firstUpdate.state));
      },
    );
  });
}

DrawState _selectedRectangleState() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: const [
        ElementState(
          id: 'rect-1',
          rect: DrawRect(maxX: 100, maxY: 100),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ],
    ),
    selection: const SelectionState(selectedIds: {'rect-1'}),
  ),
  application: ApplicationState.initial(),
);

final class _SingleOperationRegistry implements EditOperationRegistry {
  _SingleOperationRegistry(this._operation);

  final EditOperation _operation;

  @override
  Iterable<EditOperation> get allOperations => [_operation];

  @override
  Iterable<EditOperationId> get allOperationIds => [_operation.id];

  @override
  EditOperation? getOperation(EditOperationId operationId) =>
      operationId == _operation.id ? _operation : null;
}

class _GuideOnlyOperation extends EditOperation {
  @override
  EditOperationId get id => 'guide_only_test';

  @override
  _GuideOnlyContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final selectedId = state.domain.selection.selectedIds.first;
    final selected = state.domain.document.getElementById(selectedId);
    if (selected == null) {
      throw StateError('Missing selected element for guide-only context');
    }

    return _GuideOnlyContext(
      startPosition: position,
      startBounds: selected.rect,
      selectedIdsAtStart: {selectedId},
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
    );
  }

  @override
  MoveTransform initialTransform({
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
  }) {
    final zero = currentPosition.x - currentPosition.x;
    final guides = currentPosition.x > 0
        ? <SnapGuide>[_buildGuide(zero)]
        : <SnapGuide>[];
    return EditUpdateResult<EditTransform>(
      transform: MoveTransform(dx: zero, dy: zero),
      snapGuides: guides,
    );
  }

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => state.copyWith(
    application: state.application.copyWith(interaction: const IdleState()),
  );

  @override
  DrawState cancel({required DrawState state, required EditContext context}) =>
      state.copyWith(
        application: state.application.copyWith(interaction: const IdleState()),
      );

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => EditPreview.none;

  SnapGuide _buildGuide(double zero) => SnapGuide(
    kind: SnapGuideKind.point,
    axis: SnapGuideAxis.vertical,
    start: DrawPoint(x: 20 + zero, y: zero),
    end: DrawPoint(x: 20 + zero, y: 100 + zero),
    markers: [DrawPoint(x: 20 + zero, y: 50 + zero)],
  );
}

class _GuideOnlyContext extends EditContext {
  const _GuideOnlyContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
  });

  @override
  bool get hasSnapshots => true;
}

class _GuideOnlyParams extends EditOperationParams {
  const _GuideOnlyParams();
}
