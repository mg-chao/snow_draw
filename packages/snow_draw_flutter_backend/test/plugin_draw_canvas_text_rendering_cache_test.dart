import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'updates canvas render keys when text rendering caches are invalidated',
    (tester) async {
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

      final dynamicBefore = _dynamicRenderKey(tester);
      final baselineRevision = dynamicBefore.textRenderingCacheRevision;

      invalidateTextRenderingCaches();
      await tester.pump();

      final dynamicAfter = _dynamicRenderKey(tester);
      final expectedRevision = baselineRevision + 1;
      expect(dynamicAfter.textRenderingCacheRevision, expectedRevision);
    },
  );
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
