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
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/render_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginDrawCanvas watermark hover behavior', () {
    late DefaultDrawStore store;

    setUp(() async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      store = DefaultDrawStore(context: context);
      await _createRectangle(store);
    });

    tearDown(() {
      store.dispose();
    });

    testWidgets('selection mode shows hover selection preview', (tester) async {
      await _pumpCanvas(
        tester: tester,
        store: store,
        currentToolTypeId: null,
        isSelectionToolActive: true,
      );

      await _hoverAt(tester, const Offset(170, 120));
      expect(_dynamicRenderKey(tester).hoveredElementId, isNotNull);
    });

    testWidgets('watermark mode suppresses hover selection preview', (
      tester,
    ) async {
      await _pumpCanvas(
        tester: tester,
        store: store,
        currentToolTypeId: null,
        isSelectionToolActive: false,
      );

      await _hoverAt(tester, const Offset(170, 120));
      expect(_dynamicRenderKey(tester).hoveredElementId, isNull);
    });
  });
}

Future<void> _pumpCanvas({
  required WidgetTester tester,
  required DefaultDrawStore store,
  required ElementTypeId<ElementData>? currentToolTypeId,
  required bool isSelectionToolActive,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PluginDrawCanvas(
          size: const Size(320, 240),
          store: store,
          currentToolTypeId: currentToolTypeId,
          isSelectionToolActive: isSelectionToolActive,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _createRectangle(DefaultDrawStore store) async {
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
  await store.dispatch(const ClearSelection());
}

Future<void> _hoverAt(WidgetTester tester, Offset position) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await tester.pump();
  await mouse.moveTo(position);
  await tester.pump();
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
