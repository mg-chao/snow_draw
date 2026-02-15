import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/middleware/default_middlewares.dart';
import 'package:snow_draw_core/draw/input/middleware/input_middleware.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InputPipeline safety guards', () {
    test('creates a defensive copy of middleware list', () {
      final source = <InputMiddleware>[const ValidationMiddleware()];
      final pipeline = InputPipeline(middlewares: source);

      source.add(const LoggingMiddleware());

      expect(pipeline.middlewares.length, 1);
    });

    test('intercepts when middleware calls next more than once', () async {
      final counter = _InvocationCounter();
      final pipeline = InputPipeline(
        middlewares: [
          const _DoubleNextMiddleware(),
          _CountingMiddleware(counter: counter),
        ],
      );

      final result = await pipeline.execute(_event, _context());

      expect(counter.value, 1);
      expect(result, isNull);
    });

    test('waits for downstream completion when next is detached', () async {
      final gate = Completer<void>();
      final counter = _InvocationCounter();
      final pipeline = InputPipeline(
        middlewares: [
          const _DetachedNextMiddleware(),
          _GateMiddleware(counter: counter, gate: gate),
        ],
      );

      var completed = false;
      final future = pipeline.execute(_event, _context()).then((value) {
        completed = true;
        return value;
      });

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(completed, isFalse);
      expect(counter.value, 1);

      gate.complete();
      final result = await future;

      expect(result, isNull);
    });

    test('handles deep middleware chains without stack overflow', () async {
      final pipeline = InputPipeline(
        middlewares: List<InputMiddleware>.generate(
          1800,
          (_) => const _PassThroughMiddleware(),
        ),
      );

      final result = await pipeline.execute(_event, _context());

      expect(result, same(_event));
    });
  });
}

MiddlewareContext _context() => MiddlewareContext(state: DrawState());

const _event = PointerMoveInputEvent(
  position: DrawPoint(x: 12, y: 24),
  modifiers: KeyModifiers.none,
);

class _DoubleNextMiddleware extends InputMiddlewareBase {
  const _DoubleNextMiddleware() : super(name: 'DoubleNext');

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    await next(event);
    return next(event);
  }
}

class _DetachedNextMiddleware extends InputMiddlewareBase {
  const _DetachedNextMiddleware() : super(name: 'DetachedNext');

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    unawaited(next(event));
    return event;
  }
}

class _CountingMiddleware extends InputMiddlewareBase {
  const _CountingMiddleware({required this.counter}) : super(name: 'Counting');

  final _InvocationCounter counter;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) {
    counter.value += 1;
    return next(event);
  }
}

class _GateMiddleware extends InputMiddlewareBase {
  const _GateMiddleware({required this.counter, required this.gate})
    : super(name: 'Gate');

  final _InvocationCounter counter;
  final Completer<void> gate;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    counter.value += 1;
    await gate.future;
    return next(event);
  }
}

class _PassThroughMiddleware extends InputMiddlewareBase {
  const _PassThroughMiddleware() : super(name: 'PassThrough');

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) => next(event);
}

class _InvocationCounter {
  var value = 0;
}
