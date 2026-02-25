import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

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

      final keyBefore = _canvasRenderKey(tester);
      final baselineRevision = keyBefore.textRenderingCacheRevision;

      invalidateTextRenderingCaches();
      await tester.pump();

      final keyAfter = _canvasRenderKey(tester);
      final expectedRevision = baselineRevision + 1;
      expect(keyAfter.textRenderingCacheRevision, expectedRevision);
    },
  );
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
