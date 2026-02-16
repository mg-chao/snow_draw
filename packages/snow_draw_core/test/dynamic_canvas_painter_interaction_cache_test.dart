import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_definition.dart';
import 'package:snow_draw_core/draw/elements/core/element_hit_tester.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_renderer.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
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

DynamicCanvasRenderKey _buildRenderKey({
  required DrawState state,
  required DefaultElementRegistry registry,
  required Map<String, ElementState> previewElementsById,
}) => DynamicCanvasRenderKey(
  creatingElement: null,
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
  optimizedDynamicElementIds: const <String>{},
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
