import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/render_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('free draw creating state populates dynamic key and advances '
      'creation revision', (tester) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(size: const Size(320, 240), store: store),
        ),
      ),
    );
    await tester.pump();

    final beforeCreate = _dynamicRenderKey(tester);
    expect(beforeCreate.creatingElement, isNull);

    await store.dispatch(
      const CreateElement(
        typeId: FreeDrawData.typeIdToken,
        position: DrawPoint(x: 24, y: 24),
      ),
    );
    await tester.pump();

    final startedCreate = _dynamicRenderKey(tester);
    final startedCreatingElement = startedCreate.creatingElement;
    expect(startedCreatingElement, isNotNull);
    expect(startedCreatingElement!.element.data, isA<FreeDrawData>());
    final startingRevision = startedCreatingElement.creationRevision;

    await store.dispatch(
      const UpdateCreatingElement(currentPosition: DrawPoint(x: 88, y: 72)),
    );
    await tester.pump();

    final movedCreate = _dynamicRenderKey(tester);
    final movedCreatingElement = movedCreate.creatingElement;
    expect(movedCreatingElement, isNotNull);
    expect(
      movedCreatingElement!.creationRevision,
      greaterThan(startingRevision),
    );
  });
}

DynamicCanvasRenderKey _dynamicRenderKey(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is DynamicCanvasPainter) {
      return painter.renderKey;
    }
  }
  throw StateError('DynamicCanvasPainter not found');
}
