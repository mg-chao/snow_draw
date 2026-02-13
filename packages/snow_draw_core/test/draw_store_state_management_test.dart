import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_base.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_context.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_pipeline.dart';
import 'package:snow_draw_core/draw/store/selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultDrawStore state management', () {
    test('select on disposed store throws before evaluating the selector', () {
      final store = _createStore()..dispose();

      var selectorCallCount = 0;
      final selector = SimpleSelector<DrawState, int>((state) {
        selectorCallCount += 1;
        return state.domain.selection.selectionVersion;
      });

      expect(() => store.select(selector, (_) {}), throwsA(isA<StateError>()));
      expect(selectorCallCount, 0);
    });

    test(
      'dispatch queue processes actions strictly in enqueue order',
      () async {
        final trace = <String>[];
        final pipeline = MiddlewarePipeline(
          middlewares: [
            _RecordingDelayMiddleware(
              trace: trace,
              delay: const Duration(milliseconds: 5),
            ),
          ],
        );
        final store = _createStore(pipeline: pipeline);
        addTearDown(store.dispose);

        final dispatches = <Future<void>>[
          for (var i = 0; i < 5; i++)
            store.dispatch(MoveCamera(dx: i.toDouble(), dy: 0)),
        ];

        await Future.wait(dispatches);

        expect(
          trace,
          equals([
            'start:0',
            'end:0',
            'start:1',
            'end:1',
            'start:2',
            'end:2',
            'start:3',
            'end:3',
            'start:4',
            'end:4',
          ]),
        );
      },
    );
  });
}

DefaultDrawStore _createStore({MiddlewarePipeline? pipeline}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, pipeline: pipeline);
}

class _RecordingDelayMiddleware extends MiddlewareBase {
  const _RecordingDelayMiddleware({required this.trace, required this.delay});

  final List<String> trace;
  final Duration delay;

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    final action = context.action;
    if (action is MoveCamera) {
      trace.add('start:${action.dx.toInt()}');
    } else {
      trace.add('start:${action.runtimeType}');
    }
    await Future<void>.delayed(delay);
    final nextContext = await next(context);
    if (action is MoveCamera) {
      trace.add('end:${action.dx.toInt()}');
    } else {
      trace.add('end:${action.runtimeType}');
    }
    return nextContext;
  }
}
