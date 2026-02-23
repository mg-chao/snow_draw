import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses static segments for non-highlight preview interactions', () {
    final counter = _RenderCounter();
    final registry = _buildRegistry(counter);
    final elements = <ElementState>[
      const ElementState(
        id: 'cache-static-1',
        rect: DrawRect(maxX: 40, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: _CacheTestData(),
      ),
      const ElementState(
        id: 'cache-dynamic',
        rect: DrawRect(minX: 50, maxX: 90, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: _CacheTestData(),
      ),
      const ElementState(
        id: 'cache-static-2',
        rect: DrawRect(minX: 100, maxX: 140, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: _CacheTestData(),
      ),
    ];
    final state = _buildState(elements: elements, elementsVersion: 424242);

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 52, minY: 2, maxX: 92, maxY: 42),
    );
    _paintPreviewFrame(state: state, registry: registry, preview: firstPreview);
    expect(counter.count, 3);

    counter.reset();
    final secondPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 80, minY: 20, maxX: 120, maxY: 60),
    );
    _paintPreviewFrame(
      state: state,
      registry: registry,
      preview: secondPreview,
    );

    // Only the dynamic preview element should be repainted on the second
    // frame; static ranges come from the interaction-scene cache.
    expect(counter.count, 1);
  });

  test(
    'falls back when preview enters viewport from an offscreen base element',
    () {
      final counter = _RenderCounter();
      final registry = _buildRegistry(counter);
      final elements = <ElementState>[
        const ElementState(
          id: 'cache-visible',
          rect: DrawRect(maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: _CacheTestData(),
        ),
        const ElementState(
          id: 'cache-offscreen',
          rect: DrawRect(minX: 420, minY: 20, maxX: 460, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: _CacheTestData(),
        ),
      ];
      final state = _buildState(elements: elements, elementsVersion: 898989);

      final preview = elements[1].copyWith(
        rect: const DrawRect(minX: 60, minY: 20, maxX: 100, maxY: 60),
      );
      _paintPreviewFrame(state: state, registry: registry, preview: preview);

      // The offscreen persisted element must still be painted once its preview
      // moves into the viewport.
      expect(counter.count, 2);
    },
  );

  test('reuses static segments when serial connectors are visible', () {
    final counter = _RenderCounter();
    final registry = _buildRegistryWithSerialSupport(counter);
    final elements = <ElementState>[
      const ElementState(
        id: 'serial-text',
        rect: DrawRect(minX: 180, minY: 80, maxX: 260, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(text: 'connector target'),
      ),
      const ElementState(
        id: 'serial-node',
        rect: DrawRect(minX: 60, minY: 84, maxX: 96, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: SerialNumberData(textElementId: 'serial-text'),
      ),
      const ElementState(
        id: 'cache-static',
        rect: DrawRect(minX: 280, minY: 40, maxX: 340, maxY: 100),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: _CacheTestData(),
      ),
    ];
    final state = _buildState(elements: elements, elementsVersion: 314159);

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 70, minY: 92, maxX: 106, maxY: 128),
    );
    _paintPreviewFrame(state: state, registry: registry, preview: firstPreview);
    expect(counter.count, 3);

    counter.reset();
    final secondPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 92, minY: 108, maxX: 128, maxY: 144),
    );
    _paintPreviewFrame(
      state: state,
      registry: registry,
      preview: secondPreview,
    );

    // Serial connector rendering keeps both the preview serial node and
    // its bound text dynamic. Cached static segments should still be reused.
    expect(counter.count, 2);
  });

  test(
    'promotes bound text when serial preview gains binding after cache warm-up',
    () {
      final counter = _RenderCounter();
      final registry = _buildRegistryWithSerialSupport(counter);
      final elements = <ElementState>[
        const ElementState(
          id: 'text-preview-target',
          rect: DrawRect(minX: 180, minY: 80, maxX: 260, maxY: 120),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: TextData(text: 'connector target'),
        ),
        const ElementState(
          id: 'serial-node',
          rect: DrawRect(minX: 70, minY: 88, maxX: 106, maxY: 124),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: SerialNumberData(),
        ),
        const ElementState(
          id: 'cache-static',
          rect: DrawRect(minX: 40, minY: 50, maxX: 110, maxY: 120),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: _CacheTestData(),
        ),
      ];
      final state = _buildState(elements: elements, elementsVersion: 424000);

      final unboundSerialPreview = elements[1].copyWith(
        rect: const DrawRect(minX: 78, minY: 96, maxX: 114, maxY: 132),
      );
      _paintPreviewFrame(
        state: state,
        registry: registry,
        preview: unboundSerialPreview,
      );
      expect(counter.count, 3);

      counter.reset();
      final serialPreview = elements[1].copyWith(
        data: const SerialNumberData(textElementId: 'text-preview-target'),
      );
      _paintPreviewFrame(
        state: state,
        registry: registry,
        preview: serialPreview,
      );

      // Introducing a serial preview must invalidate the static context so the
      // bound text is promoted to the dynamic set together with the
      // serial node.
      expect(counter.count, 2);
    },
  );

  test('keeps unaffected serial connector texts on cached static segments', () {
    final counter = _RenderCounter();
    final registry = _buildRegistryWithSerialSupport(counter);
    final elements = <ElementState>[
      const ElementState(
        id: 'text-a',
        rect: DrawRect(minX: 180, minY: 80, maxX: 260, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(text: 'connector A'),
      ),
      const ElementState(
        id: 'serial-a',
        rect: DrawRect(minX: 60, minY: 84, maxX: 96, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: SerialNumberData(textElementId: 'text-a'),
      ),
      const ElementState(
        id: 'text-b',
        rect: DrawRect(minX: 20, minY: 150, maxX: 100, maxY: 190),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: TextData(text: 'connector B'),
      ),
      const ElementState(
        id: 'serial-b',
        rect: DrawRect(minX: 110, minY: 154, maxX: 146, maxY: 190),
        rotation: 0,
        opacity: 1,
        zIndex: 3,
        data: SerialNumberData(textElementId: 'text-b'),
      ),
      const ElementState(
        id: 'cache-static',
        rect: DrawRect(minX: 200, minY: 30, maxX: 260, maxY: 90),
        rotation: 0,
        opacity: 1,
        zIndex: 4,
        data: _CacheTestData(),
      ),
    ];
    final state = _buildState(elements: elements, elementsVersion: 271828);

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 72, minY: 96, maxX: 108, maxY: 132),
    );
    _paintPreviewFrame(state: state, registry: registry, preview: firstPreview);
    expect(counter.count, 5);

    counter.reset();
    final secondPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 96, minY: 112, maxX: 132, maxY: 148),
    );
    _paintPreviewFrame(
      state: state,
      registry: registry,
      preview: secondPreview,
    );

    // Only the moved serial and its own bound text should be dynamic.
    expect(counter.count, 2);
  });

  test('whole-scene highlight preview keeps cached static scene '
      'when preview exits viewport', () {
    final counter = _RenderCounter();
    final registry = _buildRegistryWithHighlightSupport(counter);
    final elements = <ElementState>[
      const ElementState(
        id: 'cache-static-1',
        rect: DrawRect(maxX: 40, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: _CacheTestData(),
      ),
      const ElementState(
        id: 'cache-highlight',
        rect: DrawRect(minX: 50, maxX: 90, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: HighlightData(),
      ),
      const ElementState(
        id: 'cache-static-2',
        rect: DrawRect(minX: 100, maxX: 140, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: _CacheTestData(),
      ),
    ];
    final state = _buildState(elements: elements, elementsVersion: 777777);

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 60, minY: 10, maxX: 100, maxY: 50),
    );
    _paintPreviewFrame(state: state, registry: registry, preview: firstPreview);
    expect(counter.count, 3);

    counter.reset();
    final offscreenPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 400, minY: 400, maxX: 440, maxY: 440),
    );
    _paintPreviewFrame(
      state: state,
      registry: registry,
      preview: offscreenPreview,
    );

    // Static ranges stay cached and the offscreen preview is culled.
    expect(counter.count, 0);
  });

  test(
    'creating filter preview paints without mutating cached scene lists',
    () {
      final counter = _RenderCounter();
      final registry = _buildRegistry(counter);
      const persisted = ElementState(
        id: 'cache-static-1',
        rect: DrawRect(maxX: 40, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: _CacheTestData(),
      );
      const creatingElement = ElementState(
        id: 'new-filter',
        rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(),
      );
      final interaction = CreatingState(
        element: creatingElement,
        startPosition: const DrawPoint(x: 20, y: 20),
        currentRect: const DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 90),
      );
      final state = _buildState(
        elements: const [persisted],
        elementsVersion: 7,
        interaction: interaction,
      );

      expect(
        () => _paintFrame(
          stateView: DrawStateView.fromState(state),
          renderKey: _buildRenderKey(
            state: state,
            registry: registry,
            previewElementsById: const <String, ElementState>{},
            creatingElement: const CreatingElementSnapshot(
              element: creatingElement,
              currentRect: DrawRect(minX: 20, minY: 20, maxX: 90, maxY: 90),
            ),
          ),
        ),
        returnsNormally,
      );
    },
  );
}

DrawState _buildState({
  required List<ElementState> elements,
  required int elementsVersion,
  InteractionState? interaction,
}) {
  final application = ApplicationState.initial();
  return DrawState.fromLayers(
    domain: DomainState(
      document: DocumentState(
        elements: elements,
        elementsVersion: elementsVersion,
      ),
    ),
    application: interaction == null
        ? application
        : application.copyWith(interaction: interaction),
  );
}

void _paintPreviewFrame({
  required DrawState state,
  required DefaultElementRegistry registry,
  required ElementState preview,
}) {
  final previewElementsById = <String, ElementState>{preview.id: preview};
  _paintFrame(
    stateView: _buildPreviewStateView(
      state: state,
      previewElementsById: previewElementsById,
    ),
    renderKey: _buildRenderKey(
      state: state,
      registry: registry,
      previewElementsById: previewElementsById,
    ),
  );
}

DrawStateView _buildPreviewStateView({
  required DrawState state,
  required Map<String, ElementState> previewElementsById,
}) => DrawStateView.withPreview(
  state: state,
  previewElementsById: previewElementsById,
  effectiveSelection: EffectiveSelection.none,
  snapGuides: const [],
);

DefaultElementRegistry _buildRegistry(_RenderCounter counter) =>
    DefaultElementRegistry()..register<_CacheTestData>(
      ElementDefinition<_CacheTestData>(
        typeId: _CacheTestData.typeIdToken,
        displayName: 'cache-test',
        hitTester: const _CacheHitTester(),
        createDefaultData: _CacheTestData.new,
        fromJson: (_) => const _CacheTestData(),
        taskEncoder: _CountingTaskEncoder<_CacheTestData>(counter),
      ),
    );

DefaultElementRegistry _buildRegistryWithSerialSupport(
  _RenderCounter counter,
) => _buildRegistry(counter)
  ..register<TextData>(
    ElementDefinition<TextData>(
      typeId: TextData.typeIdToken,
      displayName: 'text',
      hitTester: const _CacheHitTester(),
      createDefaultData: TextData.new,
      fromJson: TextData.fromJson,
      taskEncoder: _CountingTaskEncoder<TextData>(counter),
    ),
  )
  ..register<SerialNumberData>(
    ElementDefinition<SerialNumberData>(
      typeId: SerialNumberData.typeIdToken,
      displayName: 'serial',
      hitTester: const _CacheHitTester(),
      createDefaultData: SerialNumberData.new,
      fromJson: SerialNumberData.fromJson,
      taskEncoder: _CountingTaskEncoder<SerialNumberData>(counter),
    ),
  );

DefaultElementRegistry _buildRegistryWithHighlightSupport(
  _RenderCounter counter,
) => _buildRegistry(counter)
  ..register<HighlightData>(
    ElementDefinition<HighlightData>(
      typeId: HighlightData.typeIdToken,
      displayName: 'highlight',
      hitTester: const _CacheHitTester(),
      createDefaultData: HighlightData.new,
      fromJson: HighlightData.fromJson,
      taskEncoder: _CountingTaskEncoder<HighlightData>(counter),
    ),
  );

DynamicCanvasRenderKey _buildRenderKey({
  required DrawState state,
  required DefaultElementRegistry registry,
  required Map<String, ElementState> previewElementsById,
  CreatingElementSnapshot? creatingElement,
}) => DynamicCanvasRenderKey(
  creatingElement: creatingElement,
  effectiveSelection: EffectiveSelection.none,
  boxSelectionBounds: null,
  selectedIds: const <String>{},
  hoveredElementId: null,
  hoveredBindingElementId: null,
  hoveredArrowHandle: null,
  activeArrowHandle: null,
  arrowDeleteIndicatorVisible: false,
  hoverSelectionConfig: const SelectionConfig(),
  snapGuides: const [],
  documentVersion: state.domain.document.elementsVersion,
  textRenderingCacheRevision: 0,
  camera: state.application.view.camera,
  previewElementsById: previewElementsById,
  scaleFactor: 1,
  selectionConfig: const SelectionConfig(),
  boxSelectionConfig: const BoxSelectionConfig(),
  snapConfig: const SnapConfig(),
  canvasConfig: const CanvasConfig(),
  gridConfig: const GridConfig(),
  isHighlightMaskVisible: false,
  highlightMaskConfig: const HighlightMaskConfig(),
  isWatermarkVisible: false,
  watermarkConfig: const WatermarkConfig(),
  elementRegistry: registry,
  performanceMonitoringEnabled: false,
);

void _paintFrame({
  required DrawStateView stateView,
  required DynamicCanvasRenderKey renderKey,
}) {
  final painter = DynamicCanvasPainter(
    renderKey: renderKey,
    stateView: stateView,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, const ui.Size(300, 200));
  recorder.endRecording().dispose();
}

class _RenderCounter {
  var count = 0;

  void increment() => count += 1;

  void reset() => count = 0;
}

class _CountingTaskEncoder<T extends ElementData>
    implements ElementRenderTaskEncoder<T> {
  _CountingTaskEncoder(this._counter);

  final _RenderCounter _counter;

  @override
  List<RenderTask> encodeTasks({
    required ElementState element,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    _counter.increment();
    return <RenderTask>[
      RectangleRenderTask(
        element: element,
        data: const RectangleData(
          color: DrawColor(0xFF1576FE),
          fillColor: DrawColor(0x221576FE),
        ),
        localeTag: localeTag,
      ),
    ];
  }
}

class _CacheHitTester implements ElementHitTester {
  const _CacheHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) => element.rect
      .copyWith(
        minX: element.rect.minX - tolerance,
        minY: element.rect.minY - tolerance,
        maxX: element.rect.maxX + tolerance,
        maxY: element.rect.maxY + tolerance,
      )
      .containsPoint(position);

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}

class _CacheTestData extends ElementData {
  const _CacheTestData();

  static const typeIdToken = ElementTypeId<_CacheTestData>('cache-test');

  @override
  ElementTypeId<_CacheTestData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => const {'type': 'cache-test'};

  @override
  bool operator ==(Object other) => other is _CacheTestData;

  @override
  int get hashCode => 0;
}
