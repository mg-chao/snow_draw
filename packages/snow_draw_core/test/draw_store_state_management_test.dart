import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_base.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_context.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_pipeline.dart';
import 'package:snow_draw_core/draw/store/selector.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

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

    test(
      'select can scope selector evaluation to specific change types',
      () async {
        final store = _createStore(initialState: _stateWithSelectableElement());
        addTearDown(store.dispose);

        var selectorCallCount = 0;
        var listenerCallCount = 0;
        final selector = SimpleSelector<DrawState, int>((state) {
          selectorCallCount += 1;
          return state.domain.selection.selectionVersion;
        });

        final unsubscribe = store.select(
          selector,
          (_) => listenerCallCount += 1,
          changeTypes: {DrawStateChange.selection},
        );
        addTearDown(unsubscribe);

        expect(selectorCallCount, 1);
        expect(listenerCallCount, 0);

        await store.dispatch(const MoveCamera(dx: 24, dy: -12));
        expect(selectorCallCount, 1);
        expect(listenerCallCount, 0);

        await store.dispatch(const SelectAll());
        expect(selectorCallCount, 2);
        expect(listenerCallCount, 1);
      },
    );

    test(
      'select keeps legacy behavior when change types are not provided',
      () async {
        final store = _createStore(initialState: _stateWithSelectableElement());
        addTearDown(store.dispose);

        var selectorCallCount = 0;
        var listenerCallCount = 0;
        final selector = SimpleSelector<DrawState, int>((state) {
          selectorCallCount += 1;
          return state.domain.selection.selectionVersion;
        });

        final unsubscribe = store.select(
          selector,
          (_) => listenerCallCount += 1,
        );
        addTearDown(unsubscribe);

        expect(selectorCallCount, 1);
        expect(listenerCallCount, 0);

        await store.dispatch(const MoveCamera(dx: 18, dy: 6));
        expect(selectorCallCount, 2);
        expect(listenerCallCount, 0);

        await store.dispatch(const SelectAll());
        expect(selectorCallCount, 3);
        expect(listenerCallCount, 1);
      },
    );
  });
}

DefaultDrawStore _createStore({
  MiddlewarePipeline? pipeline,
  DrawState? initialState,
}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(
    context: context,
    pipeline: pipeline,
    initialState: initialState,
  );
}

DrawState _stateWithSelectableElement() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: const [
        ElementState(
          id: 'selectable',
          rect: DrawRect(maxX: 48, maxY: 36),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ],
    ),
  ),
);

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
