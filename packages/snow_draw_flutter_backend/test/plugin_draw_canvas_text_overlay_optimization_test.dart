import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/plugin_draw_canvas.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'text-only draft updates refresh canvas render keys when geometry is '
    'unchanged',
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

      final keyBefore = _canvasRenderKey(tester);

      await store.dispatch(
        const UpdateTextEdit(text: 'hello world', rect: rect),
      );
      await tester.pump();

      final keyAfter = _canvasRenderKey(tester);

      expect(keyAfter, isNot(equals(keyBefore)));
    },
  );

  testWidgets('text draft geometry updates refresh canvas render keys', (
    tester,
  ) async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);

    const textData = TextData(text: 'hello');
    const initialRect = DrawRect(minX: 32, minY: 24, maxX: 180, maxY: 72);
    const updatedRect = DrawRect(minX: 32, minY: 24, maxX: 220, maxY: 96);
    const element = ElementState(
      id: 'text-1',
      rect: initialRect,
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
          rect: initialRect,
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

    final keyBefore = _canvasRenderKey(tester);

    await store.dispatch(
      const UpdateTextEdit(text: 'hello world', rect: updatedRect),
    );
    await tester.pump();

    final keyAfter = _canvasRenderKey(tester);

    expect(keyAfter, isNot(equals(keyBefore)));
  });

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
          fillColor: DrawColor(Colors.yellow.withValues(alpha: 0.3).toARGB32()),
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

  testWidgets(
    'text draft geometry uses context text metrics service for preview rect',
    (tester) async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      const metricsService = _DeterministicTextMetricsService();
      final context = DrawContext.withDefaults(
        elementRegistry: registry,
        textMetricsService: metricsService,
      );
      const initialData = TextData(text: 'seed', autoResize: true);
      const initialRect = DrawRect(minX: 20, minY: 16, maxX: 140, maxY: 64);
      const editedText = 'metrics-service';
      final store = DefaultDrawStore(
        context: context,
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'text-1',
                  rect: initialRect,
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: initialData,
                ),
              ],
            ),
            selection: const SelectionState(selectedIds: {'text-1'}),
          ),
          application: const ApplicationState(
            view: ViewState(),
            interaction: TextEditingState(
              elementId: 'text-1',
              draftData: initialData,
              rect: initialRect,
              isNew: false,
              opacity: 1,
              rotation: 0,
            ),
          ),
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

      final textField = tester.widget<TextField>(find.byType(TextField));
      textField.controller!.text = editedText;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final interaction = store.state.application.interaction;
      expect(interaction, isA<TextEditingState>());
      final editing = interaction as TextEditingState;
      expect(editing.draftData.text, editedText);

      final expectedRect = resolveTextEditingRect(
        origin: DrawPoint(x: initialRect.minX, y: initialRect.minY),
        currentRect: initialRect,
        data: const TextData(text: editedText, autoResize: true),
        textMetricsService: metricsService,
        allowShrinkHeight: true,
      );
      expect(editing.rect, expectedRect);
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

final class _DeterministicTextMetricsService implements TextMetricsService {
  const _DeterministicTextMetricsService();

  static const _lineHeight = 28.0;

  @override
  TextMetrics measure(TextLayoutRequest request) {
    final textLines = request.data.text.isEmpty
        ? const ['']
        : request.data.text.split('\n');
    final lines = <TextLineMetrics>[];
    var maxWidth = 0.0;
    for (final line in textLines) {
      final lineWidth = 70 + line.length * 13;
      final constrainedLineWidth =
          request.maxWidth.isFinite && lineWidth > request.maxWidth
          ? request.maxWidth
          : lineWidth.toDouble();
      if (constrainedLineWidth > maxWidth) {
        maxWidth = constrainedLineWidth;
      }
      lines.add(
        TextLineMetrics(width: constrainedLineWidth, height: _lineHeight),
      );
    }

    final minWidth = request.minWidth;
    if (minWidth != null && minWidth.isFinite && maxWidth < minWidth) {
      maxWidth = minWidth;
    }

    return TextMetrics(
      width: maxWidth,
      height: _lineHeight * lines.length,
      lineHeight: _lineHeight,
      lines: List<TextLineMetrics>.unmodifiable(lines),
    );
  }

  @override
  void clearCaches() {}
}
