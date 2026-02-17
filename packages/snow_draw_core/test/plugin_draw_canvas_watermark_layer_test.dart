import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/selection_overlay_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/selector.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/static_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/watermark_canvas_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'watermark-only updates repaint overlay without rebuilding scene painters',
    (tester) async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      addTearDown(store.dispose);

      await _pumpCanvas(tester: tester, store: store);

      final staticBefore = _staticPainter(tester);
      final dynamicBefore = _dynamicPainter(tester);
      final watermarkBefore = _watermarkPainter(tester);

      await store.dispatch(
        const UpdateGlobalElements(
          watermark: WatermarkConfig(
            text: 'CONFIDENTIAL',
            angle: 24,
            gap: 80,
            opacity: 0.2,
          ),
        ),
      );
      await tester.pump();

      final staticAfter = _staticPainter(tester);
      final dynamicAfter = _dynamicPainter(tester);
      final watermarkAfter = _watermarkPainter(tester);

      expect(identical(staticBefore, staticAfter), isTrue);
      expect(identical(dynamicBefore, dynamicAfter), isTrue);
      expect(identical(watermarkBefore, watermarkAfter), isTrue);
      expect(watermarkAfter.controller.state.config.text, 'CONFIDENTIAL');
      expect(watermarkAfter.controller.state.isVisible, isTrue);
    },
  );

  testWidgets(
    'preview listenable repaints watermark overlay without store mutation',
    (tester) async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      final preview = ValueNotifier<WatermarkConfig?>(null);
      addTearDown(store.dispose);
      addTearDown(preview.dispose);

      await _pumpCanvas(
        tester: tester,
        store: store,
        watermarkPreviewListenable: preview,
      );

      final staticBefore = _staticPainter(tester);
      final dynamicBefore = _dynamicPainter(tester);
      final watermarkBefore = _watermarkPainter(tester);

      preview.value = const WatermarkConfig(text: 'LIVE', opacity: 0.25);
      await tester.pump();

      final staticAfter = _staticPainter(tester);
      final dynamicAfter = _dynamicPainter(tester);
      final watermarkAfter = _watermarkPainter(tester);

      expect(identical(staticBefore, staticAfter), isTrue);
      expect(identical(dynamicBefore, dynamicAfter), isTrue);
      expect(identical(watermarkBefore, watermarkAfter), isTrue);
      expect(watermarkAfter.controller.state.config.text, 'LIVE');
      expect(watermarkAfter.controller.state.isVisible, isTrue);
      expect(
        store.state.domain.document.globalElements.watermark.text,
        isEmpty,
      );
    },
  );

  testWidgets('watermark visibility toggles through layer controller '
      'without scene rebuild', (tester) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    addTearDown(store.dispose);

    await store.dispatch(
      const UpdateGlobalElements(
        watermark: WatermarkConfig(text: 'DRAFT', opacity: 0.2),
      ),
    );
    await _pumpCanvas(tester: tester, store: store);

    final staticBefore = _staticPainter(tester);
    final dynamicBefore = _dynamicPainter(tester);
    final watermarkBefore = _watermarkPainter(tester);
    expect(watermarkBefore.controller.state.isVisible, isTrue);

    await store.dispatch(
      const UpdateGlobalElements(watermark: WatermarkConfig()),
    );
    await tester.pump();

    final staticAfter = _staticPainter(tester);
    final dynamicAfter = _dynamicPainter(tester);
    final watermarkAfter = _watermarkPainter(tester);

    expect(identical(staticBefore, staticAfter), isTrue);
    expect(identical(dynamicBefore, dynamicAfter), isTrue);
    expect(identical(watermarkBefore, watermarkAfter), isTrue);
    expect(watermarkAfter.controller.state.isVisible, isFalse);
  });

  testWidgets('watermark updates keep static scene stable '
      'while refreshing dynamic overlays for selection changes', (
    tester,
  ) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = _ManualStateDrawStore(context: context);
    addTearDown(store.dispose);

    await _pumpCanvas(tester: tester, store: store);

    final staticBefore = _staticPainter(tester);
    final dynamicBefore = _dynamicPainter(tester);
    final watermarkBefore = _watermarkPainter(tester);

    final currentState = store.state;
    store.emitState(
      currentState.copyWith(
        domain: currentState.domain.copyWith(
          document: currentState.domain.document.copyWith(
            globalElements: currentState.domain.document.globalElements
                .copyWith(
                  watermark: const WatermarkConfig(
                    text: 'AUDIT',
                    angle: 15,
                    opacity: 0.2,
                  ),
                ),
          ),
        ),
        application: currentState.application.copyWith(
          selectionOverlay: const SelectionOverlayState(
            multiSelectOverlay: MultiSelectOverlayState(
              bounds: DrawRect(minX: 12, minY: 18, maxX: 148, maxY: 132),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final staticAfter = _staticPainter(tester);
    final dynamicAfter = _dynamicPainter(tester);
    final watermarkAfter = _watermarkPainter(tester);

    expect(identical(staticBefore, staticAfter), isTrue);
    expect(identical(dynamicBefore, dynamicAfter), isFalse);
    expect(identical(watermarkBefore, watermarkAfter), isTrue);
    expect(watermarkAfter.controller.state.config.text, 'AUDIT');
  });
}

Future<void> _pumpCanvas({
  required WidgetTester tester,
  required DrawStore store,
  ValueNotifier<WatermarkConfig?>? watermarkPreviewListenable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PluginDrawCanvas(
          size: const Size(320, 240),
          store: store,
          isSelectionToolActive: false,
          watermarkPreviewListenable: watermarkPreviewListenable,
        ),
      ),
    ),
  );
  await tester.pump();
}

StaticCanvasPainter _staticPainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is StaticCanvasPainter) {
      return painter;
    }
  }
  throw StateError('StaticCanvasPainter not found');
}

DynamicCanvasPainter _dynamicPainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is DynamicCanvasPainter) {
      return painter;
    }
  }
  throw StateError('DynamicCanvasPainter not found');
}

WatermarkCanvasPainter _watermarkPainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is WatermarkCanvasPainter) {
      return painter;
    }
  }
  throw StateError('WatermarkCanvasPainter not found');
}

class _ManualStateDrawStore implements DrawStore {
  _ManualStateDrawStore({required this.context});

  @override
  final DrawContext context;

  var _state = DrawState();
  final _config = DrawConfig();
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _listeners = <StateChangeListener<DrawState>>[];

  @override
  DrawState get state => _state;

  @override
  DrawState get currentState => _state;

  @override
  DrawConfig get config => _config;

  @override
  Stream<DrawConfig> get configStream => _configController.stream;

  @override
  Stream<DrawEvent> get eventStream => _eventController.stream;

  @override
  Stream<T> eventStreamOf<T extends DrawEvent>() =>
      eventStream.where((event) => event is T).cast<T>();

  @override
  StreamSubscription<T> onEvent<T extends DrawEvent>(
    void Function(T event) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => eventStreamOf<T>().listen(
    handler,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> call(DrawAction action) => dispatch(action);

  @override
  Future<void> dispatch(DrawAction action) async {}

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _listeners.remove(listener);
  }

  @override
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
    Set<DrawStateChange>? changeTypes,
  }) {
    var previous = selector.select(_state);
    return listen((state) {
      final next = selector.select(state);
      final compare = equals ?? selector.equals;
      if (!compare(previous, next)) {
        previous = next;
        listener(next);
      }
    }, changeTypes: changeTypes);
  }

  void emitState(DrawState nextState) {
    _state = nextState;
    for (final listener in List<StateChangeListener<DrawState>>.from(
      _listeners,
    )) {
      listener(nextState);
    }
  }

  Future<void> dispose() async {
    _listeners.clear();
    await _configController.close();
    await _eventController.close();
  }
}
