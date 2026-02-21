import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/static_canvas_painter.dart';

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
      final staticBefore = _staticRenderKey(tester);
      final baselineRevision = dynamicBefore.textRenderingCacheRevision;
      expect(staticBefore.textRenderingCacheRevision, baselineRevision);

      invalidateTextRenderingCaches();
      await tester.pump();

      final dynamicAfter = _dynamicRenderKey(tester);
      final staticAfter = _staticRenderKey(tester);
      final expectedRevision = baselineRevision + 1;
      expect(dynamicAfter.textRenderingCacheRevision, expectedRevision);
      expect(staticAfter.textRenderingCacheRevision, expectedRevision);
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

StaticCanvasRenderKey _staticRenderKey(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is StaticCanvasPainter) {
      return painter.renderKey;
    }
  }
  throw StateError('StaticCanvasPainter not found');
}
