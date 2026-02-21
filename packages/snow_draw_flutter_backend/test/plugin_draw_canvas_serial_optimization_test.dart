import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('serial edit forces localized dynamic-scene optimization even '
      'for small dynamic tails', (tester) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(
      context: context,
      initialState: _buildSerialEditingInitialState(),
    );
    addTearDown(store.dispose);

    await store.dispatch(
      const StartEdit(
        operationId: EditOperationIds.move,
        position: DrawPoint(x: 30, y: 30),
        params: MoveOperationParams(),
      ),
    );
    await store.dispatch(
      const UpdateEdit(currentPosition: DrawPoint(x: 42, y: 36)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(
            size: const Size(360, 240),
            store: store,
            currentToolTypeId: SerialNumberData.typeIdToken,
            isSelectionToolActive: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final dynamicPainter = _dynamicPainter(tester);
    expect(dynamicPainter.renderKey.optimizedDynamicElementIds, {'serial-1'});
    expect(dynamicPainter.renderKey.dynamicLayerStartIndex, isNull);
  });
}

DrawState _buildSerialEditingInitialState() {
  const serial = ElementState(
    id: 'serial-1',
    rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: SerialNumberData(number: 7),
  );
  const backgroundA = ElementState(
    id: 'rect-1',
    rect: DrawRect(minX: 110, minY: 20, maxX: 170, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  );
  const backgroundB = ElementState(
    id: 'rect-2',
    rect: DrawRect(minX: 180, minY: 20, maxX: 240, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: RectangleData(),
  );
  const backgroundC = ElementState(
    id: 'rect-3',
    rect: DrawRect(minX: 250, minY: 20, maxX: 310, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 3,
    data: RectangleData(),
  );

  return DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: const [serial, backgroundA, backgroundB, backgroundC],
        elementsVersion: 41,
      ),
      selection: const SelectionState(selectedIds: {'serial-1'}),
    ),
  );
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
