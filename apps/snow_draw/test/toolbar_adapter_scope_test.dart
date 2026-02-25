import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mask-only update does not emit UpdateElementsStyle validation errors',
    () async {
      final store = _createStore(selectedIds: const {'h1'});
      final adapter = StyleToolbarAdapter(store: store);
      final validationEvents = <ValidationFailedEvent>[];
      final subscription = store.eventStream
          .where((event) => event is ValidationFailedEvent)
          .cast<ValidationFailedEvent>()
          .listen(validationEvents.add);

      addTearDown(subscription.cancel);
      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        maskOpacity: 0.6,
        toolType: ToolType.highlight,
      );
      await pumpEventQueue();

      expect(
        validationEvents.where(
          (event) => event.action == 'UpdateElementsStyle',
        ),
        isEmpty,
      );
      expect(
        store.state.domain.document.globalElements.highlightMask.maskOpacity,
        closeTo(0.6, 0.0001),
      );
    },
  );

  test(
    'highlights-only scope does not mutate selected text stroke width',
    () async {
      final store = _createStore(selectedIds: const {'h1', 't1'});
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        textStrokeWidth: 0,
        toolType: ToolType.highlight,
        scope: StyleUpdateScope.highlightsOnly,
      );
      await pumpEventQueue();

      final highlightData = store.state.domain.document
          .getElementById('h1')
          ?.data;
      final textData = store.state.domain.document.getElementById('t1')?.data;

      expect(highlightData, isA<HighlightData>());
      expect(textData, isA<TextData>());

      final highlight = highlightData! as HighlightData;
      final text = textData! as TextData;

      expect(highlight.strokeWidth, 0);
      expect(text.strokeWidth, 3);
    },
  );

  test(
    'texts-only scope does not mutate selected highlight stroke width',
    () async {
      final store = _createStore(selectedIds: const {'h1', 't1'});
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        textStrokeWidth: 5,
        toolType: ToolType.text,
        scope: StyleUpdateScope.textsOnly,
      );
      await pumpEventQueue();

      final highlightData = store.state.domain.document
          .getElementById('h1')
          ?.data;
      final textData = store.state.domain.document.getElementById('t1')?.data;

      expect(highlightData, isA<HighlightData>());
      expect(textData, isA<TextData>());

      final highlight = highlightData! as HighlightData;
      final text = textData! as TextData;

      expect(highlight.strokeWidth, 2);
      expect(text.strokeWidth, 5);
    },
  );

  test(
    'filters-only scope does not mutate selected text stroke width',
    () async {
      final store = _createStore(selectedIds: const {'f1', 't1'});
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        filterType: CanvasFilterType.inversion,
        toolType: ToolType.filter,
        scope: StyleUpdateScope.filtersOnly,
      );
      await pumpEventQueue();

      final filterData = store.state.domain.document.getElementById('f1')?.data;
      final textData = store.state.domain.document.getElementById('t1')?.data;

      expect(filterData, isA<FilterData>());
      expect(textData, isA<TextData>());

      final filter = filterData! as FilterData;
      final text = textData! as TextData;

      expect(filter.type, CanvasFilterType.inversion);
      expect(text.strokeWidth, 3);
    },
  );

  test('watermark gap update clamps to minimum value', () async {
    final store = _createStore(selectedIds: const <String>{});
    final adapter = StyleToolbarAdapter(store: store);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await adapter.applyStyleUpdate(
      watermarkGap: 2,
      toolType: ToolType.watermark,
    );
    await pumpEventQueue();

    expect(
      store.state.domain.document.globalElements.watermark.gap,
      ConfigDefaults.minWatermarkGap,
    );
  });
}

DefaultDrawStore _createStore({required Set<String> selectedIds}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  const highlight = ElementState(
    id: 'h1',
    rect: DrawRect(maxX: 100, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: HighlightData(strokeWidth: 2),
  );
  const text = ElementState(
    id: 't1',
    rect: DrawRect(minX: 120, maxX: 220, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: TextData(strokeWidth: 3),
  );
  const filter = ElementState(
    id: 'f1',
    rect: DrawRect(minX: 240, maxX: 320, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: FilterData(),
  );

  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [highlight, text, filter]),
      selection: SelectionState(selectedIds: selectedIds),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
