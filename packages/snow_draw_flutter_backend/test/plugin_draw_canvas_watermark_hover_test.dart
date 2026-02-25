import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

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
      expect(_hasHoverSelectionPreview(_canvasRenderKey(tester)), isTrue);
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
      expect(_hasHoverSelectionPreview(_canvasRenderKey(tester)), isFalse);
    });

    testWidgets('switching to watermark mode uses basic canvas cursor', (
      tester,
    ) async {
      await _pumpCanvas(
        tester: tester,
        store: store,
        currentToolTypeId: null,
        isSelectionToolActive: true,
      );
      expect(_canvasCursor(tester), SystemMouseCursors.precise);

      await _pumpCanvas(
        tester: tester,
        store: store,
        currentToolTypeId: null,
        isSelectionToolActive: false,
      );
      expect(_canvasCursor(tester), SystemMouseCursors.basic);
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
      initialData: RectangleData(fillColor: DrawColor(0x401576FE)),
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

SceneCanvasRenderKey _canvasRenderKey(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is SceneCanvasPainter) {
      return painter.renderKey;
    }
  }
  throw StateError('SceneCanvasPainter not found');
}

MouseCursor _canvasCursor(WidgetTester tester) {
  final mouseRegionFinder = find.descendant(
    of: find.byType(PluginDrawCanvas),
    matching: find.byType(MouseRegion),
  );
  return tester.widget<MouseRegion>(mouseRegionFinder).cursor;
}

bool _hasHoverSelectionPreview(SceneCanvasRenderKey renderKey) {
  for (final task in renderKey.framePlan.tasks) {
    if (task is HoverOutlineRenderTask) {
      return true;
    }
  }
  return false;
}
