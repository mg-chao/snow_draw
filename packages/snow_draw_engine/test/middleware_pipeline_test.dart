import 'package:snow_draw_engine/draw/actions/draw_actions.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/store/history_manager.dart';
import 'package:snow_draw_engine/draw/store/middleware/middleware_base.dart';
import 'package:snow_draw_engine/draw/store/middleware/middleware_context.dart';
import 'package:snow_draw_engine/draw/store/middleware/middleware_pipeline.dart';
import 'package:snow_draw_engine/draw/store/snapshot_builder.dart';
import 'package:test/test.dart';

void main() {
  group('MiddlewarePipeline', () {
    test('returns initial context when pipeline has no middleware', () async {
      final pipeline = MiddlewarePipeline(middlewares: const []);
      final initialContext = _createInitialContext();

      final result = await pipeline.execute(initialContext);

      expect(result, same(initialContext));
    });

    test('creates a defensive copy of middleware list', () {
      final source = <Middleware>[const _PassThroughMiddleware()];
      final pipeline = MiddlewarePipeline(middlewares: source);

      source.add(const _PassThroughMiddleware());

      expect(pipeline.length, 1);
    });

    test('stops pipeline when middleware invoke throws', () async {
      final counter = _InvocationCounter();
      final pipeline = MiddlewarePipeline(
        middlewares: [
          const _ThrowingInvokeMiddleware(),
          _CountingMiddleware(counter: counter),
        ],
      );

      final result = await pipeline.execute(_createInitialContext());

      expect(result.hasError, isTrue);
      expect(result.error, isA<FormatException>());
      expect(result.errorSource, 'ThrowInvoke');
      expect(counter.value, 0);
    });

    test(
      'does not execute middleware when context is already stopped',
      () async {
        final counter = _InvocationCounter();
        final pipeline = MiddlewarePipeline(
          middlewares: [_CountingMiddleware(counter: counter)],
        );
        final stoppedContext = _createInitialContext().withStop(
          'already stopped',
        );

        final result = await pipeline.execute(stoppedContext);

        expect(counter.value, 0);
        expect(result, same(stoppedContext));
      },
    );

    test(
      'does not execute middleware when context already has error',
      () async {
        final counter = _InvocationCounter();
        final pipeline = MiddlewarePipeline(
          middlewares: [_CountingMiddleware(counter: counter)],
        );
        final stackTrace = StackTrace.current;
        final failedContext = _createInitialContext().withError(
          StateError('existing failure'),
          stackTrace,
          source: 'preExisting',
        );

        final result = await pipeline.execute(failedContext);

        expect(counter.value, 0);
        expect(result, same(failedContext));
        expect(result.errorSource, 'preExisting');
      },
    );

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
      'captures post-next middleware errors without re-running downstream',
      () async {
        final counter = _InvocationCounter();
        final pipeline = MiddlewarePipeline(
          middlewares: [
            const _ThrowAfterNextMiddleware(),
            _CountingMiddleware(counter: counter),
            const _OffsetStateMiddleware(dx: 1),
          ],
        );

        final result = await pipeline.execute(_createInitialContext());

        expect(counter.value, 1);
        expect(result.hasError, isTrue);
        expect(result.error, isA<FormatException>());
        expect(result.errorSource, 'ThrowAfterNext');
        expect(_cameraX(result.currentState), 6);
      },
    );

    test(
      'preserves downstream context when middleware stops after next',
      () async {
        final pipeline = MiddlewarePipeline(
          middlewares: const [
            _StateErrorAfterNextMiddleware(),
            _OffsetStateMiddleware(dx: 4),
          ],
        );

        final result = await pipeline.execute(_createInitialContext());

        expect(result.hasError, isTrue);
        expect(result.error, isA<StateError>());
        expect(result.errorSource, 'StateErrorAfterNext');
        expect(_cameraX(result.currentState), 6);
      },
    );

    test(
      'sortByPriority keeps descending priority and stable tie ordering',
      () {
        final pipeline = MiddlewarePipeline(
          middlewares: const [
            _PriorityMiddleware(name: 'low', priority: -10),
            _PriorityMiddleware(name: 'high', priority: 100),
            _PriorityMiddleware(name: 'midA', priority: 50),
            _PriorityMiddleware(name: 'midB', priority: 50),
          ],
        );

        final sorted = pipeline.sortByPriority();

        expect(
          sorted.middlewares.map((middleware) => middleware.name),
          equals(['high', 'midA', 'midB', 'low']),
        );
      },
    );

    test('sortByPriority returns same pipeline when already sorted', () {
      final pipeline = MiddlewarePipeline(
        middlewares: const [
          _PriorityMiddleware(name: 'high', priority: 100),
          _PriorityMiddleware(name: 'mid', priority: 10),
          _PriorityMiddleware(name: 'low', priority: -5),
        ],
      );

      final sorted = pipeline.sortByPriority();

      expect(sorted, same(pipeline));
    });

    test('handles deep middleware chains without stack overflow', () async {
      final pipeline = MiddlewarePipeline(
        middlewares: List<Middleware>.generate(
          200,
          (_) => const _PassThroughMiddleware(),
        ),
      );

      final result = await pipeline.execute(_createInitialContext());

      expect(result.hasError, isFalse);
    });
  });
}

DispatchContext _createInitialContext() {
  final drawContext = DrawContext.withDefaults();
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

double _cameraX(DrawState state) => state.application.view.camera.position.x;

DispatchContext _offsetContextState(DispatchContext context, double dx) {
  final state = context.currentState;
  final nextState = state.copyWith(
    application: state.application.copyWith(
      view: state.application.view.copyWith(
        camera: state.application.view.camera.translated(dx, 0),
      ),
    ),
  );
  return context.withCurrentState(nextState);
}

class _ThrowingInvokeMiddleware extends MiddlewareBase {
  const _ThrowingInvokeMiddleware();

  @override
  String get name => 'ThrowInvoke';

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      Future<DispatchContext>.error(const FormatException('Bad invoke'));
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
    await next(_offsetContextState(context, 5));
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
    await next(_offsetContextState(context, 2));
    throw StateError('Bad invoke after next');
  }
}

class _OffsetStateMiddleware extends MiddlewareBase {
  const _OffsetStateMiddleware({required this.dx});

  final double dx;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      next(_offsetContextState(context, dx));
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

class _PriorityMiddleware extends MiddlewareBase {
  const _PriorityMiddleware({required this.name, required this.priority});

  @override
  final String name;

  @override
  final int priority;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      next(context);
}

class _PassThroughMiddleware extends MiddlewareBase {
  const _PassThroughMiddleware();

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) =>
      next(context);
}

class _InvocationCounter {
  var value = 0;
}
