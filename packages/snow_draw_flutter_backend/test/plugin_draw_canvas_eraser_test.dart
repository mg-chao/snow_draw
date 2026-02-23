import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/static_canvas_painter.dart';

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

        final staticPainter = _staticPainter(tester);
        expect(staticPainter.renderKey.skipBaseElementScene, isTrue);
        final dynamicPainter = _dynamicPainter(tester);
        expect(dynamicPainter.renderKey.dynamicLayerStartIndex, 0);
        final previewElement =
            dynamicPainter.renderKey.previewElementsById[elementId];
        expect(previewElement, isNotNull);
        expect(previewElement!.opacity, closeTo(0.3, 0.0001));

        await mouse.up();
        await tester.pump();
        await tester.pump();

        expect(store.state.domain.document.getElementById(elementId), isNull);
      },
    );

    testWidgets('erases elements along long move paths in a single stroke', (
      tester,
    ) async {
      final leftId = await _createRectangle(
        store,
        start: const DrawPoint(x: 30, y: 70),
        end: const DrawPoint(x: 70, y: 110),
      );
      final middleId = await _createRectangle(
        store,
        start: const DrawPoint(x: 120, y: 70),
        end: const DrawPoint(x: 160, y: 110),
      );
      final rightId = await _createRectangle(
        store,
        start: const DrawPoint(x: 210, y: 70),
        end: const DrawPoint(x: 250, y: 110),
      );

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

      await mouse.down(const Offset(50, 90));
      await tester.pump();
      await mouse.moveTo(const Offset(230, 90));
      await tester.pump();
      await mouse.up();
      await tester.pump();
      await tester.pump();

      final document = store.state.domain.document;
      expect(document.getElementById(leftId), isNull);
      expect(document.getElementById(middleId), isNull);
      expect(document.getElementById(rightId), isNull);
    });

    testWidgets(
      'keeps sweep precision for narrow strokes between sampled points',
      (tester) async {
        const lineId = 'edge-line';
        final registry = DefaultElementRegistry();
        registerBuiltInElements(registry);
        final context = DrawContext.withDefaults(elementRegistry: registry);
        final localStore = DefaultDrawStore(
          context: context,
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: lineId,
                    rect: DrawRect(
                      minX: 54,
                      minY: 97.9,
                      maxX: 54.1,
                      maxY: 97.9,
                    ),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: LineData(strokeWidth: 0.1),
                  ),
                ],
              ),
            ),
          ),
        );
        addTearDown(localStore.dispose);

        await _pumpCanvas(
          tester: tester,
          store: localStore,
          currentToolTypeId: null,
          isSelectionToolActive: false,
          isEraserToolActive: true,
        );

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        await mouse.down(const Offset(50, 90));
        await tester.pump();
        await mouse.moveTo(const Offset(66, 90));
        await tester.pump();
        await mouse.up();
        await tester.pump();
        await tester.pump();

        final document = localStore.state.domain.document;
        expect(document.getElementById(lineId), isNull);
      },
    );

    testWidgets(
      'keeps static layer stable while previewing additional erased elements',
      (tester) async {
        final firstId = await _createRectangle(
          store,
          start: const DrawPoint(x: 30, y: 70),
          end: const DrawPoint(x: 70, y: 110),
        );
        final secondId = await _createRectangle(
          store,
          start: const DrawPoint(x: 210, y: 70),
          end: const DrawPoint(x: 250, y: 110),
        );

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

        await mouse.down(const Offset(50, 90));
        await tester.pump();

        final staticPainterBeforeMove = _staticPainter(tester);

        await mouse.moveTo(const Offset(230, 90));
        await tester.pump();

        final staticPainterAfterMove = _staticPainter(tester);
        expect(
          identical(staticPainterBeforeMove, staticPainterAfterMove),
          isTrue,
        );

        final dynamicPainter = _dynamicPainter(tester);
        expect(
          dynamicPainter.renderKey.previewElementsById[firstId],
          isNotNull,
        );
        expect(
          dynamicPainter.renderKey.previewElementsById[secondId],
          isNotNull,
        );

        await mouse.up();
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets('does not interpolate between concurrent eraser pointers', (
      tester,
    ) async {
      final leftId = await _createRectangle(
        store,
        start: const DrawPoint(x: 30, y: 70),
        end: const DrawPoint(x: 70, y: 110),
      );
      final middleId = await _createRectangle(
        store,
        start: const DrawPoint(x: 120, y: 70),
        end: const DrawPoint(x: 160, y: 110),
      );
      final rightId = await _createRectangle(
        store,
        start: const DrawPoint(x: 210, y: 70),
        end: const DrawPoint(x: 250, y: 110),
      );

      await _pumpCanvas(
        tester: tester,
        store: store,
        currentToolTypeId: null,
        isSelectionToolActive: false,
        isEraserToolActive: true,
      );

      final firstTouch = await tester.startGesture(const Offset(50, 90));
      final secondTouch = await tester.startGesture(const Offset(230, 90));
      await tester.pump();

      await firstTouch.up();
      await secondTouch.up();
      await tester.pump();
      await tester.pump();

      final document = store.state.domain.document;
      expect(document.getElementById(leftId), isNull);
      expect(document.getElementById(middleId), isNotNull);
      expect(document.getElementById(rightId), isNull);
    });
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
  DrawPoint start = const DrawPoint(x: 120, y: 80),
  DrawPoint end = const DrawPoint(x: 220, y: 160),
}) async {
  await store.dispatch(
    CreateElement(
      typeId: RectangleData.typeIdToken,
      position: start,
      initialData: const RectangleData(fillColor: DrawColor(0x401576FE)),
    ),
  );
  await store.dispatch(UpdateCreatingElement(currentPosition: end));
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

MouseCursor _canvasCursor(WidgetTester tester) {
  final mouseRegionFinder = find.descendant(
    of: find.byType(PluginDrawCanvas),
    matching: find.byType(MouseRegion),
  );
  return tester.widget<MouseRegion>(mouseRegionFinder).cursor;
}
