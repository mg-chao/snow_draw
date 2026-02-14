import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/history_manager.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_base.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_context.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_pipeline.dart';
import 'package:snow_draw_core/draw/store/snapshot_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiddlewarePipeline', () {
    test('creates a defensive copy of middleware list', () {
      final source = <Middleware>[const _FlagMetadataMiddleware('first')];
      final pipeline = MiddlewarePipeline(middlewares: source);

      source.add(const _FlagMetadataMiddleware('second'));

      expect(pipeline.length, 1);
    });

    test('skips middleware when invoke throws FormatException', () async {
      final pipeline = MiddlewarePipeline(
        middlewares: const [
          _ThrowingInvokeMiddleware(),
          _FlagMetadataMiddleware('afterInvokeError'),
        ],
      );

      final result = await pipeline.execute(_createInitialContext());

      expect(result.hasError, isFalse);
      expect(result.getMetadata<bool>('skipped_ThrowInvoke'), isTrue);
      expect(result.getMetadata<bool>('afterInvokeError'), isTrue);
    });

    test('routes shouldExecute errors through error handler', () async {
      final pipeline = MiddlewarePipeline(
        middlewares: const [
          _ThrowingShouldExecuteMiddleware(),
          _FlagMetadataMiddleware('afterShouldExecuteError'),
        ],
      );

      final result = await pipeline.execute(_createInitialContext());

      expect(result.hasError, isFalse);
      expect(result.getMetadata<bool>('skipped_ThrowShouldExecute'), isTrue);
      expect(result.getMetadata<bool>('afterShouldExecuteError'), isTrue);
    });

    test('prevents invoking next more than once', () async {
      final counter = _InvocationCounter();
      final pipeline = MiddlewarePipeline(
        middlewares: [
          const _DoubleNextMiddleware(),
          _CountingMiddleware(counter: counter),
        ],
      );

      final result = await pipeline.execute(_createInitialContext());

      expect(counter.value, 1);
      expect(result.hasError, isTrue);
      expect(result.error, isA<StateError>());
      expect(result.errorSource, 'DoubleNext');
    });

    test(
      'fails when middleware completes before downstream next settles',
      () async {
        final counter = _InvocationCounter();
        final pipeline = MiddlewarePipeline(
          middlewares: [
            const _DetachedNextMiddleware(),
            _DelayedCountingMiddleware(
              counter: counter,
              delay: const Duration(milliseconds: 1),
            ),
          ],
        );

        final result = await pipeline.execute(_createInitialContext());

        expect(counter.value, 1);
        expect(result.hasError, isTrue);
        expect(result.error, isA<StateError>());
        expect(result.errorSource, 'DetachedNext');
      },
    );

    test(
      'does not re-run downstream middleware when skipping after next',
      () async {
        final counter = _InvocationCounter();
        final pipeline = MiddlewarePipeline(
          middlewares: [
            const _ThrowAfterNextMiddleware(),
            _CountingMiddleware(counter: counter),
          ],
        );

        final result = await pipeline.execute(_createInitialContext());

        expect(counter.value, 1);
        expect(result.hasError, isFalse);
        expect(result.getMetadata<bool>('fromThrowAfterNext'), isTrue);
        expect(result.getMetadata<bool>('skipped_ThrowAfterNext'), isTrue);
      },
    );

    test(
      'preserves downstream context when middleware stops after next',
      () async {
        final pipeline = MiddlewarePipeline(
          middlewares: const [
            _StateErrorAfterNextMiddleware(),
            _FlagMetadataMiddleware('downstreamReached'),
          ],
        );

        final result = await pipeline.execute(_createInitialContext());

        expect(result.hasError, isTrue);
        expect(result.error, isA<StateError>());
        expect(result.errorSource, 'StateErrorAfterNext');
        expect(result.getMetadata<bool>('stateErrorAfterNext'), isTrue);
        expect(result.getMetadata<bool>('downstreamReached'), isTrue);
      },
    );
  });
}

DispatchContext _createInitialContext() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final drawContext = DrawContext.withDefaults(elementRegistry: registry);
  final historyManager = HistoryManager(logService: drawContext.log);
  const snapshotBuilder = SnapshotBuilder();
  final editSessionService = EditSessionService.fromRegistry(
    drawContext.editOperations,
    configProvider: () => drawContext.config,
    logService: drawContext.log,
  );

  return DispatchContext.initial(
    action: const MoveCamera(dx: 1, dy: 0),
    state: DrawState(),
    drawContext: drawContext,
    historyManager: historyManager,
    snapshotBuilder: snapshotBuilder,
    editSessionService: editSessionService,
    sessionIdGenerator: () => 'session_0',
    isBatching: false,
    includeSelectionInHistory: false,
  );
}

class _ThrowingInvokeMiddleware extends MiddlewareBase {
  const _ThrowingInvokeMiddleware();

  @override
  String get name => 'ThrowInvoke';

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      Future<DispatchContext>.error(const FormatException('Bad invoke'));
}

class _ThrowingShouldExecuteMiddleware extends MiddlewareBase {
  const _ThrowingShouldExecuteMiddleware();

  @override
  String get name => 'ThrowShouldExecute';

  @override
  bool shouldExecute(DispatchContext context) {
    throw const FormatException('Bad shouldExecute');
  }

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      next(context);
}

class _FlagMetadataMiddleware extends MiddlewareBase {
  const _FlagMetadataMiddleware(this.key);

  final String key;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    final updated = context.withMetadata(key, true);
    return next(updated);
  }
}

class _DoubleNextMiddleware extends MiddlewareBase {
  const _DoubleNextMiddleware();

  @override
  String get name => 'DoubleNext';

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    await next(context);
    return next(context);
  }
}

class _ThrowAfterNextMiddleware extends MiddlewareBase {
  const _ThrowAfterNextMiddleware();

  @override
  String get name => 'ThrowAfterNext';

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    await next(context.withMetadata('fromThrowAfterNext', true));
    throw const FormatException('Bad invoke after next');
  }
}

class _StateErrorAfterNextMiddleware extends MiddlewareBase {
  const _StateErrorAfterNextMiddleware();

  @override
  String get name => 'StateErrorAfterNext';

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    await next(context.withMetadata('stateErrorAfterNext', true));
    throw StateError('Bad invoke after next');
  }
}

class _DetachedNextMiddleware extends MiddlewareBase {
  const _DetachedNextMiddleware();

  @override
  String get name => 'DetachedNext';

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    unawaited(next(context.withMetadata('detachedNextCalled', true)));
    return context;
  }
}

class _DelayedCountingMiddleware extends MiddlewareBase {
  const _DelayedCountingMiddleware({
    required this.counter,
    required this.delay,
  });

  final _InvocationCounter counter;
  final Duration delay;

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    counter.value += 1;
    await Future<void>.delayed(delay);
    return next(context.withMetadata('downstreamReached', true));
  }
}

class _CountingMiddleware extends MiddlewareBase {
  const _CountingMiddleware({required this.counter});

  final _InvocationCounter counter;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    counter.value += 1;
    return next(context);
  }
}

class _InvocationCounter {
  var value = 0;
}
