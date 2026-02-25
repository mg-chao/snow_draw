import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offscreen style updates refresh canvas render key', (
    tester,
  ) async {
    final store = _createStoreWithVisibleAndOffscreenElements();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(size: const Size(320, 240), store: store),
        ),
      ),
    );
    await tester.pump();

    final before = _scenePainter(tester);

    await store.dispatch(
      UpdateElementsStyle(
        elementIds: const ['offscreen-rect'],
        color: const DrawColor(0xFFFF0000),
      ),
    );
    await tester.pump();

    final after = _scenePainter(tester);

    expect(after.renderKey, isNot(equals(before.renderKey)));
    expect(after.shouldRepaint(before), isTrue);
  });

  testWidgets('visible style updates refresh canvas render key', (
    tester,
  ) async {
    final store = _createStoreWithVisibleAndOffscreenElements();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(size: const Size(320, 240), store: store),
        ),
      ),
    );
    await tester.pump();

    final before = _scenePainter(tester);

    await store.dispatch(
      UpdateElementsStyle(
        elementIds: const ['visible-rect'],
        color: const DrawColor(0xFFFF0000),
      ),
    );
    await tester.pump();

    final after = _scenePainter(tester);

    expect(after.renderKey, isNot(equals(before.renderKey)));
    expect(after.shouldRepaint(before), isTrue);
  });
}

DefaultDrawStore _createStoreWithVisibleAndOffscreenElements() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  const visibleRect = ElementState(
    id: 'visible-rect',
    rect: DrawRect(minX: 16, minY: 16, maxX: 96, maxY: 96),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(color: DrawColor(0xFF2F80ED)),
  );
  const offscreenRect = ElementState(
    id: 'offscreen-rect',
    rect: DrawRect(minX: 2000, minY: 2000, maxX: 2080, maxY: 2080),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(color: DrawColor(0xFF27AE60)),
  );
  return DefaultDrawStore(
    context: context,
    initialState: DrawState(
      domain: DomainState(
        document: DocumentState(elements: const [visibleRect, offscreenRect]),
      ),
    ),
  );
}

SceneCanvasPainter _scenePainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter is SceneCanvasPainter) {
      return painter;
    }
  }
  throw StateError('SceneCanvasPainter not found');
}
