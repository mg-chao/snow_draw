import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/models/view_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_core/ui/canvas/render_keys.dart';
import 'package:snow_draw_core/ui/canvas/static_canvas_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'text draft updates keep canvas render keys stable during editing',
    (tester) async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      const textData = TextData(text: 'hello');
      const rect = DrawRect(minX: 32, minY: 24, maxX: 180, maxY: 72);
      const element = ElementState(
        id: 'text-1',
        rect: rect,
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: textData,
      );
      final initialState = DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [element]),
          selection: const SelectionState(selectedIds: {'text-1'}),
        ),
        application: const ApplicationState(
          view: ViewState(),
          interaction: TextEditingState(
            elementId: 'text-1',
            draftData: textData,
            rect: rect,
            isNew: false,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );
      final store = DefaultDrawStore(
        context: context,
        initialState: initialState,
      );
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

      await store.dispatch(const UpdateTextEdit(text: 'hello world'));
      await tester.pump();

      final dynamicAfter = _dynamicRenderKey(tester);
      final staticAfter = _staticRenderKey(tester);

      expect(dynamicAfter, same(dynamicBefore));
      expect(staticAfter, same(staticBefore));
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
