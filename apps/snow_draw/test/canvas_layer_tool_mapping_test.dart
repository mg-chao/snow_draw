import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/widgets/canvas_layer.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/ui/canvas/draw_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('selection tool maps to null current tool type id', (
    tester,
  ) async {
    await pumpCanvasLayer(tester);

    expect(toolController.value, ToolType.selection);
    expect(currentToolTypeId(tester), isNull);
  });

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
    }
  });
}
