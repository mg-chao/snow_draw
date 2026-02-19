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
    'text draft updates keep canvas render keys stable when geometry is unchanged',
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

      await store.dispatch(
        const UpdateTextEdit(text: 'hello world', rect: rect),
      );
      await tester.pump();

      final dynamicAfter = _dynamicRenderKey(tester);
      final staticAfter = _staticRenderKey(tester);

      expect(dynamicAfter, same(dynamicBefore));
      expect(staticAfter, same(staticBefore));
    },
  );

  testWidgets('plain text editing skips decoration overlay painter', (
    tester,
  ) async {
    final store = _createStoreWithTextEditing(const TextData(text: 'plain'));
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(size: const Size(320, 240), store: store),
        ),
      ),
    );
    await tester.pump();

    expect(_hasEditingOverlayPainter(tester), isFalse);
  });

  testWidgets(
    'stroke or background styles keep decoration overlay painter enabled',
    (tester) async {
      final store = _createStoreWithTextEditing(
        TextData(
          text: 'decorated',
          strokeWidth: 1,
          fillColor: Colors.yellow.withValues(alpha: 0.3),
        ),
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

      expect(_hasEditingOverlayPainter(tester), isTrue);
    },
  );

  testWidgets('store swap clears pending text draft sync events', (
    tester,
  ) async {
    final primaryStore = _createStoreWithTextEditing(
      const TextData(text: 'primary'),
    );
    final secondaryStore = _createStoreWithTextEditing(
      const TextData(text: 'secondary'),
    );
    addTearDown(primaryStore.dispose);
    addTearDown(secondaryStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(
            size: const Size(320, 240),
            store: primaryStore,
          ),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.controller!.text = 'pending-primary';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginDrawCanvas(
            size: const Size(320, 240),
            store: secondaryStore,
          ),
        ),
      ),
    );
    await tester.pump();

    final interaction = secondaryStore.state.application.interaction;
    expect(interaction, isA<TextEditingState>());
    final editing = interaction as TextEditingState;
    expect(editing.draftData.text, 'secondary');
  });

  testWidgets(
    'rapid local draft edits stay aligned with the latest visible text',
    (tester) async {
      final store = _createStoreWithTextEditing(const TextData(text: 'a'));
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PluginDrawCanvas(size: const Size(320, 240), store: store),
          ),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      textField.controller!
        ..text = 'ab'
        ..text = 'a';

      await tester.pump();

      final interaction = store.state.application.interaction;
      expect(interaction, isA<TextEditingState>());
      final editing = interaction as TextEditingState;
      expect(editing.draftData.text, 'a');
    },
  );
}

DefaultDrawStore _createStoreWithTextEditing(TextData textData) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  const rect = DrawRect(minX: 32, minY: 24, maxX: 180, maxY: 72);
  final element = ElementState(
    id: 'text-1',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: textData,
  );
  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(elements: [element]),
      selection: const SelectionState(selectedIds: {'text-1'}),
    ),
    application: ApplicationState(
      view: const ViewState(),
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
  return DefaultDrawStore(context: context, initialState: initialState);
}

bool _hasEditingOverlayPainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = paint.painter;
    if (painter == null) {
      continue;
    }
    if (painter.runtimeType.toString() == '_EditingTextOverlayPainter') {
      return true;
    }
  }
  return false;
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
