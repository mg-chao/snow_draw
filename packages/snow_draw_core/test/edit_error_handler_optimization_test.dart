import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_error_handler.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_result_unified.dart';
import 'package:snow_draw_core/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_core/draw/edit/edit_operations.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  group('Edit error handling no-op optimization', () {
    test('toIdle policy keeps identity when state is already idle', () {
      final state = DrawState.initial();

      final next = EditErrorHandler.computeNextState(
        state,
        ErrorStatePolicy.toIdle,
      );

      expect(identical(next, state), isTrue);
    });

    test('cancel when not editing preserves state identity', () {
      final state = DrawState.initial();
      final service = EditSessionService(
        editOperations: DefaultEditOperationRegistry.empty(),
        configProvider: () => DrawConfig.defaultConfig,
      );

      final outcome = service.cancel(state: state);

      expect(outcome.failureReason, EditFailureReason.notEditing);
      expect(identical(outcome.state, state), isTrue);
    });

    test('finish when not editing preserves state identity', () {
      final state = DrawState.initial();
      final service = EditSessionService(
        editOperations: DefaultEditOperationRegistry.empty(),
        configProvider: () => DrawConfig.defaultConfig,
      );

      final outcome = service.finish(state: state);

      expect(outcome.failureReason, EditFailureReason.notEditing);
      expect(identical(outcome.state, state), isTrue);
    });

    test(
      'update with default toIdle policy when not editing preserves identity',
      () {
        final state = DrawState.initial();
        final service = EditSessionService(
          editOperations: DefaultEditOperationRegistry.empty(),
          configProvider: () => DrawConfig.defaultConfig,
        );

        final outcome = service.update(
          state: state,
          currentPosition: DrawPoint.zero,
        );

        expect(outcome.failureReason, EditFailureReason.notEditing);
        expect(identical(outcome.state, state), isTrue);
      },
    );

    test('update with keepState policy still preserves identity', () {
      final state = DrawState.initial();
      final service = EditSessionService(
        editOperations: DefaultEditOperationRegistry.empty(),
        configProvider: () => DrawConfig.defaultConfig,
      );

      final outcome = service.update(
        state: state,
        currentPosition: DrawPoint.zero,
        failurePolicy: EditUpdateFailurePolicy.keepState,
      );

      expect(outcome.failureReason, EditFailureReason.notEditing);
      expect(identical(outcome.state, state), isTrue);
    });
  });
}
