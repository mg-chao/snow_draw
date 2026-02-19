import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/static_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/watermark_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/watermark_visibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'watermark updates rebuild scene painters without dedicated overlay',
    (tester) async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      addTearDown(store.dispose);

      await _pumpCanvas(tester: tester, store: store);

      final staticBefore = _staticPainter(tester);
      final dynamicBefore = _dynamicPainter(tester);

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

      expect(identical(staticBefore, staticAfter), isFalse);
      expect(identical(dynamicBefore, dynamicAfter), isFalse);
      expect(_watermarkOverlayPainterCount(tester), 0);
      expect(staticAfter.renderKey.watermarkLayer, WatermarkLayer.staticLayer);
      expect(dynamicAfter.renderKey.watermarkLayer, WatermarkLayer.staticLayer);
      expect(staticAfter.renderKey.watermarkConfig.text, 'CONFIDENTIAL');
      expect(dynamicAfter.renderKey.watermarkConfig.text, 'CONFIDENTIAL');
    },
  );

  testWidgets(
    'preview listenable updates scene watermark config without store mutation',
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

      preview.value = const WatermarkConfig(text: 'LIVE', opacity: 0.25);
      await tester.pump();

      final staticAfter = _staticPainter(tester);
      final dynamicAfter = _dynamicPainter(tester);

      expect(identical(staticBefore, staticAfter), isFalse);
      expect(identical(dynamicBefore, dynamicAfter), isFalse);
      expect(_watermarkOverlayPainterCount(tester), 0);
      expect(staticAfter.renderKey.watermarkConfig.text, 'LIVE');
      expect(dynamicAfter.renderKey.watermarkConfig.text, 'LIVE');
      expect(
        store.state.domain.document.globalElements.watermark.text,
        isEmpty,
      );
    },
  );

  testWidgets('watermark is routed to dynamic layer during active creation', (
    tester,
  ) async {
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

    expect(
      _dynamicPainter(tester).renderKey.watermarkLayer,
      WatermarkLayer.staticLayer,
    );

    await store.dispatch(
      const CreateElement(
        typeId: RectangleData.typeIdToken,
        position: DrawPoint(x: 20, y: 20),
        initialData: RectangleData(),
      ),
    );
    await tester.pump();

    expect(
      _dynamicPainter(tester).renderKey.watermarkLayer,
      WatermarkLayer.dynamicLayer,
    );
    expect(
      _staticPainter(tester).renderKey.watermarkLayer,
      WatermarkLayer.dynamicLayer,
    );
    expect(_watermarkOverlayPainterCount(tester), 0);
  });
}

Future<void> _pumpCanvas({
  required WidgetTester tester,
  required DefaultDrawStore store,
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

int _watermarkOverlayPainterCount(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((paint) => paint.painter is WatermarkCanvasPainter)
    .length;
