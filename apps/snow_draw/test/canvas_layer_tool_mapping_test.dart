import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/widgets/canvas_layer.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasLayerKey = ValueKey('canvas-layer');

  late DefaultDrawStore store;
  late ToolController toolController;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = DefaultDrawStore(context: context);
    toolController = ToolController();
  });

  tearDown(() {
    toolController.dispose();
    store.dispose();
  });

  Future<void> pumpCanvasLayer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasLayer(
            key: canvasLayerKey,
            size: const Size(800, 600),
            store: store,
            toolController: toolController,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Object? currentToolTypeId(WidgetTester tester) =>
      tester.widget<DrawCanvas>(find.byType(DrawCanvas)).currentToolTypeId;

  bool isSelectionToolActive(WidgetTester tester) =>
      tester.widget<DrawCanvas>(find.byType(DrawCanvas)).isSelectionToolActive;

  bool isEraserToolActive(WidgetTester tester) =>
      tester.widget<DrawCanvas>(find.byType(DrawCanvas)).isEraserToolActive;

  testWidgets(
    'selection tool maps to null current tool type id and selection mode',
    (tester) async {
      await pumpCanvasLayer(tester);

      expect(toolController.value, ToolType.selection);
      expect(currentToolTypeId(tester), isNull);
      expect(isSelectionToolActive(tester), isTrue);
      expect(isEraserToolActive(tester), isFalse);
    },
  );

  testWidgets('drawing tools map to expected element type ids', (tester) async {
    await pumpCanvasLayer(tester);

    final expectedIds = <ToolType, Object>{
      ToolType.rectangle: RectangleData.typeIdToken,
      ToolType.arrow: ArrowData.typeIdToken,
      ToolType.line: LineData.typeIdToken,
      ToolType.freeDraw: FreeDrawData.typeIdToken,
      ToolType.highlight: HighlightData.typeIdToken,
      ToolType.text: TextData.typeIdToken,
      ToolType.serialNumber: SerialNumberData.typeIdToken,
      ToolType.filter: FilterData.typeIdToken,
    };

    for (final entry in expectedIds.entries) {
      toolController.setTool(entry.key);
      await tester.pump();
      expect(currentToolTypeId(tester), entry.value);
      expect(isSelectionToolActive(tester), isFalse);
      expect(isEraserToolActive(tester), isFalse);
    }

    toolController.setTool(ToolType.eraser);
    await tester.pump();
    expect(currentToolTypeId(tester), isNull);
    expect(isSelectionToolActive(tester), isFalse);
    expect(isEraserToolActive(tester), isTrue);

    toolController.setTool(ToolType.watermark);
    await tester.pump();
    expect(currentToolTypeId(tester), isNull);
    expect(isSelectionToolActive(tester), isFalse);
    expect(isEraserToolActive(tester), isFalse);
  });

  testWidgets('canvas layer listens to a replaced tool controller', (
    tester,
  ) async {
    await pumpCanvasLayer(tester);

    toolController.setTool(ToolType.rectangle);
    await tester.pump();
    expect(currentToolTypeId(tester), RectangleData.typeIdToken);

    final replacementController = ToolController();
    addTearDown(replacementController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasLayer(
            key: canvasLayerKey,
            size: const Size(800, 600),
            store: store,
            toolController: replacementController,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(currentToolTypeId(tester), isNull);
    expect(isSelectionToolActive(tester), isTrue);
    expect(isEraserToolActive(tester), isFalse);

    toolController.setTool(ToolType.filter);
    await tester.pump();
    expect(currentToolTypeId(tester), isNull);
    expect(isSelectionToolActive(tester), isTrue);
    expect(isEraserToolActive(tester), isFalse);

    replacementController.setTool(ToolType.filter);
    await tester.pump();
    expect(currentToolTypeId(tester), FilterData.typeIdToken);
    expect(isSelectionToolActive(tester), isFalse);
    expect(isEraserToolActive(tester), isFalse);
  });
}
