import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_definition.dart';
import 'package:snow_draw_core/draw/elements/core/element_hit_tester.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_renderer.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_canvas_painter.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_visibility.dart';
import 'package:snow_draw_core/ui/canvas/render_keys.dart';

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
    final state = DrawState.fromLayers(
      domain: DomainState(
        document: DocumentState(elements: elements, elementsVersion: 424242),
      ),
      application: ApplicationState.initial(),
    );

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 52, minY: 2, maxX: 92, maxY: 42),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {firstPreview.id: firstPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {firstPreview.id: firstPreview},
      ),
    );
    expect(counter.count, 3);

    counter.reset();
    final secondPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 80, minY: 20, maxX: 120, maxY: 60),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {secondPreview.id: secondPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {secondPreview.id: secondPreview},
      ),
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
      final state = DrawState.fromLayers(
        domain: DomainState(
          document: DocumentState(elements: elements, elementsVersion: 898989),
        ),
        application: ApplicationState.initial(),
      );

      final preview = elements[1].copyWith(
        rect: const DrawRect(minX: 60, minY: 20, maxX: 100, maxY: 60),
      );
      _paintFrame(
        stateView: DrawStateView.withPreview(
          state: state,
          previewElementsById: {preview.id: preview},
          effectiveSelection: EffectiveSelection.none,
          snapGuides: const [],
        ),
        renderKey: _buildRenderKey(
          state: state,
          registry: registry,
          previewElementsById: {preview.id: preview},
        ),
      );

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
    final state = DrawState.fromLayers(
      domain: DomainState(
        document: DocumentState(elements: elements, elementsVersion: 314159),
      ),
      application: ApplicationState.initial(),
    );

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 70, minY: 92, maxX: 106, maxY: 128),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {firstPreview.id: firstPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {firstPreview.id: firstPreview},
      ),
    );
    expect(counter.count, 3);

    counter.reset();
    final secondPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 92, minY: 108, maxX: 128, maxY: 144),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {secondPreview.id: secondPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {secondPreview.id: secondPreview},
      ),
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
      final state = DrawState.fromLayers(
        domain: DomainState(
          document: DocumentState(elements: elements, elementsVersion: 424000),
        ),
        application: ApplicationState.initial(),
      );

      final unboundSerialPreview = elements[1].copyWith(
        rect: const DrawRect(minX: 78, minY: 96, maxX: 114, maxY: 132),
      );
      _paintFrame(
        stateView: DrawStateView.withPreview(
          state: state,
          previewElementsById: {unboundSerialPreview.id: unboundSerialPreview},
          effectiveSelection: EffectiveSelection.none,
          snapGuides: const [],
        ),
        renderKey: _buildRenderKey(
          state: state,
          registry: registry,
          previewElementsById: {unboundSerialPreview.id: unboundSerialPreview},
        ),
      );
      expect(counter.count, 3);

      counter.reset();
      final serialPreview = elements[1].copyWith(
        data: const SerialNumberData(textElementId: 'text-preview-target'),
      );
      _paintFrame(
        stateView: DrawStateView.withPreview(
          state: state,
          previewElementsById: {serialPreview.id: serialPreview},
          effectiveSelection: EffectiveSelection.none,
          snapGuides: const [],
        ),
        renderKey: _buildRenderKey(
          state: state,
          registry: registry,
          previewElementsById: {serialPreview.id: serialPreview},
        ),
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
    final state = DrawState.fromLayers(
      domain: DomainState(
        document: DocumentState(elements: elements, elementsVersion: 271828),
      ),
      application: ApplicationState.initial(),
    );

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 72, minY: 96, maxX: 108, maxY: 132),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {firstPreview.id: firstPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {firstPreview.id: firstPreview},
      ),
    );
    expect(counter.count, 5);

    counter.reset();
    final secondPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 96, minY: 112, maxX: 132, maxY: 148),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {secondPreview.id: secondPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {secondPreview.id: secondPreview},
      ),
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
    final state = DrawState.fromLayers(
      domain: DomainState(
        document: DocumentState(elements: elements, elementsVersion: 777777),
      ),
      application: ApplicationState.initial(),
    );

    final firstPreview = elements[1].copyWith(
      rect: const DrawRect(minX: 60, minY: 10, maxX: 100, maxY: 50),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {firstPreview.id: firstPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {firstPreview.id: firstPreview},
      ),
    );
    expect(counter.count, 3);

    counter.reset();
    final offscreenPreview = firstPreview.copyWith(
      rect: const DrawRect(minX: 400, minY: 400, maxX: 440, maxY: 440),
    );
    _paintFrame(
      stateView: DrawStateView.withPreview(
        state: state,
        previewElementsById: {offscreenPreview.id: offscreenPreview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
      renderKey: _buildRenderKey(
        state: state,
        registry: registry,
        previewElementsById: {offscreenPreview.id: offscreenPreview},
      ),
    );

    // Static ranges stay cached and the offscreen preview is culled.
    expect(counter.count, 0);
  });

  test(
    'creating filter preview paints without mutating cached scene lists',
    () {
      final registry = _buildRegistry(_RenderCounter());
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
      final state = DrawState.fromLayers(
        domain: DomainState(
          document: DocumentState(
            elements: const [persisted],
            elementsVersion: 7,
          ),
        ),
        application: ApplicationState.initial().copyWith(
          interaction: interaction,
        ),
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

DefaultElementRegistry _buildRegistry(_RenderCounter counter) =>
    DefaultElementRegistry()..register<_CacheTestData>(
      ElementDefinition<_CacheTestData>(
        typeId: _CacheTestData.typeIdToken,
        displayName: 'cache-test',
        renderer: _CacheCountingRenderer(counter),
        hitTester: const _CacheHitTester(),
        createDefaultData: _CacheTestData.new,
        fromJson: (_) => const _CacheTestData(),
      ),
    );

DefaultElementRegistry _buildRegistryWithSerialSupport(_RenderCounter counter) {
  final registry = _buildRegistry(counter)
    ..register<TextData>(
      ElementDefinition<TextData>(
        typeId: TextData.typeIdToken,
        displayName: 'text',
        renderer: _CacheCountingRenderer(counter),
        hitTester: const _CacheHitTester(),
        createDefaultData: TextData.new,
        fromJson: TextData.fromJson,
      ),
    )
    ..register<SerialNumberData>(
      ElementDefinition<SerialNumberData>(
        typeId: SerialNumberData.typeIdToken,
        displayName: 'serial',
        renderer: _CacheCountingRenderer(counter),
        hitTester: const _CacheHitTester(),
        createDefaultData: SerialNumberData.new,
        fromJson: SerialNumberData.fromJson,
      ),
    );
  return registry;
}

DefaultElementRegistry _buildRegistryWithHighlightSupport(
  _RenderCounter counter,
) {
  final registry = _buildRegistry(counter)
    ..register<HighlightData>(
      ElementDefinition<HighlightData>(
        typeId: HighlightData.typeIdToken,
        displayName: 'highlight',
        renderer: _CacheCountingRenderer(counter),
        hitTester: const _CacheHitTester(),
        createDefaultData: HighlightData.new,
        fromJson: HighlightData.fromJson,
      ),
    );
  return registry;
}

DynamicCanvasRenderKey _buildRenderKey({
  required DrawState state,
  required DefaultElementRegistry registry,
  required Map<String, ElementState> previewElementsById,
  CreatingElementSnapshot? creatingElement,
  int? previewElementsRevision,
  Set<String>? dynamicPreviewElementIds,
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
  previewElementsRevision: previewElementsRevision,
  dynamicPreviewElementIds: dynamicPreviewElementIds,
  optimizedDynamicElementIds: const <String>{},
  optimizedSceneHasPotentialOccluders: false,
  dynamicLayerStartIndex: 0,
  rendersWholeElementScene: true,
  scaleFactor: 1,
  selectionConfig: const SelectionConfig(),
  boxSelectionConfig: const BoxSelectionConfig(),
  snapConfig: const SnapConfig(),
  highlightMaskLayer: HighlightMaskLayer.none,
  highlightMaskConfig: const HighlightMaskConfig(),
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

  void increment() {
    count += 1;
  }

  void reset() {
    count = 0;
  }
}

class _CacheCountingRenderer extends ElementTypeRenderer {
  _CacheCountingRenderer(this._counter);

  final _RenderCounter _counter;

  @override
  void render({
    required ui.Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    ui.Locale? locale,
  }) {
    _counter.increment();
  }
}

class _CacheHitTester implements ElementHitTester {
  const _CacheHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final expanded = element.rect.copyWith(
      minX: element.rect.minX - tolerance,
      minY: element.rect.minY - tolerance,
      maxX: element.rect.maxX + tolerance,
      maxY: element.rect.maxY + tolerance,
    );
    return expanded.containsPoint(position);
  }

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
