import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/plugin_core.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coalesces hover plugin dispatches to one callback per frame', (
    tester,
  ) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    final hoverCounter = _HoverCounterPlugin();

    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(
            size: const Size(320, 240),
            store: store,
            customPlugins: [hoverCounter],
          ),
        ),
      ),
    );
    // Allow the async plugin coordinator bootstrap to complete.
    await tester.pump();
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: const Offset(10, 10));
    await tester.pump();

    await mouse.moveTo(const Offset(30, 40));
    await mouse.moveTo(const Offset(80, 60));
    await mouse.moveTo(const Offset(140, 90));

    expect(hoverCounter.hoverEventCount, 0);

    await tester.pump();

    expect(hoverCounter.hoverEventCount, 1);
    expect(hoverCounter.lastPosition, const DrawPoint(x: 140, y: 90));
  });
}

class _HoverCounterPlugin extends DrawInputPlugin {
  _HoverCounterPlugin()
    : super(
        id: 'hover_counter',
        name: 'Hover Counter',
        priority: -100,
        supportedEventTypes: {PointerHoverInputEvent},
      );

  var hoverEventCount = 0;
  DrawPoint? lastPosition;

  @override
  bool canHandle(InputEvent event, DrawState state) => true;

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is! PointerHoverInputEvent) {
      return unhandled();
    }
    hoverEventCount += 1;
    lastPosition = event.position;
    return consumed(message: 'Hover counted');
  }
}
