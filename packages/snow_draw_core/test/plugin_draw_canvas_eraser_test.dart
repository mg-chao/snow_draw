import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/static_canvas_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginDrawCanvas eraser tool', () {
    late DefaultDrawStore store;

    setUp(() {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      store = DefaultDrawStore(context: context);
    });

    tearDown(() {
      store.dispose();
    });

    testWidgets(
      'marks erased elements with stacked opacity and deletes on stroke end',
      (tester) async {
        final elementId = await _createRectangle(store, opacity: 0.6);
        await _pumpCanvas(
          tester: tester,
          store: store,
          currentToolTypeId: null,
          isSelectionToolActive: false,
          isEraserToolActive: true,
        );

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        await mouse.moveTo(const Offset(170, 120));
        await tester.pump();
        expect(_canvasCursor(tester), SystemMouseCursors.none);
        expect(
          find.byKey(const ValueKey('eraser-cursor-overlay')),
          findsOneWidget,
        );

        await mouse.down(const Offset(170, 120));
        await tester.pump();

        final previewElement = _staticPainter(
          tester,
        ).renderKey.previewElementsById[elementId];
        expect(previewElement, isNotNull);
        expect(previewElement!.opacity, closeTo(0.3, 0.0001));

        await mouse.up();
        await tester.pump();
        await tester.pump();

        expect(store.state.domain.document.getElementById(elementId), isNull);
      },
    );
  });
}

Future<void> _pumpCanvas({
  required WidgetTester tester,
  required DefaultDrawStore store,
  required ElementTypeId<ElementData>? currentToolTypeId,
  required bool isSelectionToolActive,
  bool isEraserToolActive = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PluginDrawCanvas(
          size: const Size(320, 240),
          store: store,
          currentToolTypeId: currentToolTypeId,
          isSelectionToolActive: isSelectionToolActive,
          isEraserToolActive: isEraserToolActive,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<String> _createRectangle(
  DefaultDrawStore store, {
  double opacity = 1.0,
}) async {
  await store.dispatch(
    const CreateElement(
      typeId: RectangleData.typeIdToken,
      position: DrawPoint(x: 120, y: 80),
      initialData: RectangleData(fillColor: Color(0x401576FE)),
    ),
  );
  await store.dispatch(
    const UpdateCreatingElement(currentPosition: DrawPoint(x: 220, y: 160)),
  );
  await store.dispatch(const FinishCreateElement());

  final elementId = store.state.domain.document.elements.last.id;
  if (opacity != 1.0) {
    await store.dispatch(
      UpdateElementsStyle(elementIds: [elementId], opacity: opacity),
    );
  }
  await store.dispatch(const ClearSelection());
  return elementId;
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

MouseCursor _canvasCursor(WidgetTester tester) {
  final mouseRegionFinder = find.descendant(
    of: find.byType(PluginDrawCanvas),
    matching: find.byType(MouseRegion),
  );
  return tester.widget<MouseRegion>(mouseRegionFinder).cursor;
}
