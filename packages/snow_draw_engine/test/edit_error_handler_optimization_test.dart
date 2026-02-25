import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_error_handler.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_result.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_engine/draw/edit/edit_operations.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('Edit error handling no-op optimization', () {
    EditSessionService createService() => EditSessionService(
      editOperations: DefaultEditOperationRegistry.empty(),
      configProvider: () => DrawConfig.defaultConfig,
    );

    void expectNotEditingNoOp(EditOutcome outcome, DrawState state) {
      expect(outcome.failureReason, EditFailureReason.notEditing);
      expect(identical(outcome.state, state), isTrue);
    }

    test('toIdle policy keeps identity when state is already idle', () {
      final state = DrawState.initial();

      final next = EditErrorHandler.computeNextState(state, keepState: false);

      expect(identical(next, state), isTrue);
    });

    test('keepState branch keeps identity', () {
      final state = DrawState.initial();

      final next = EditErrorHandler.computeNextState(state, keepState: true);

      expect(identical(next, state), isTrue);
    });

    test('cancel when not editing preserves state identity', () {
      final state = DrawState.initial();
      final outcome = createService().cancel(state: state);
      expectNotEditingNoOp(outcome, state);
    });

    test('finish when not editing preserves state identity', () {
      final state = DrawState.initial();
      final outcome = createService().finish(state: state);
      expectNotEditingNoOp(outcome, state);
    });

    test(
      'update with default toIdle policy when not editing preserves identity',
      () {
        final state = DrawState.initial();
        final outcome = createService().update(
          state: state,
          currentPosition: DrawPoint.zero,
        );

        expectNotEditingNoOp(outcome, state);
      },
    );

    test('update when not editing preserves identity', () {
      final state = DrawState.initial();
      final outcome = createService().update(
        state: state,
        currentPosition: DrawPoint.zero,
      );

      expectNotEditingNoOp(outcome, state);
    });
  });
}
