import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/highlight_mask_visibility.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/interaction_dynamic_scene_cache.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/watermark_visibility.dart';

void main() {
  group('resolveInteractionDynamicSceneFromCachedKey', () {
    test('uses optimized preview resolver when cached optimized ids exist', () {
      final stateView = _buildStateView();
      final previousRenderKey = _buildDynamicRenderKey(
        optimizedDynamicElementIds: const {'rect'},
        optimizedSceneHasPotentialOccluders: true,
        dynamicLayerStartIndex: null,
        rendersWholeElementScene: false,
        highlightMaskLayer: HighlightMaskLayer.dynamicLayer,
        watermarkLayer: WatermarkLayer.dynamicLayer,
      );
      var optimizedResolverCalled = false;
      var layerStartResolverCalled = false;
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        previousRenderKey: previousRenderKey,
        resolvePreviewByLayerStart: (view, dynamicLayerStartIndex) {
          layerStartResolverCalled = true;
          return const <String, ElementState>{};
        },
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) {
          optimizedResolverCalled = true;
          expect(
            optimizedElementIds,
            previousRenderKey.optimizedDynamicElementIds,
          );
          return {'rect': _rectangle(id: 'rect')};
        },
        resolveDynamicPreviewElementIds: (view, previewElementsById) {
          expect(previewElementsById.keys, contains('rect'));
          return {'rect'};
        },
      );

      expect(optimizedResolverCalled, isTrue);
      expect(layerStartResolverCalled, isFalse);
      expect(scene.previewElementsById.keys, contains('rect'));
      expect(scene.dynamicPreviewElementIds, {'rect'});
      expect(scene.optimizedDynamicElementIds, {'rect'});
      expect(scene.optimizedSceneHasPotentialOccluders, isTrue);
      expect(scene.dynamicLayerStartIndex, isNull);
      expect(scene.rendersWholeElementScene, isFalse);
      expect(scene.highlightMaskLayer, HighlightMaskLayer.dynamicLayer);
      expect(scene.watermarkLayer, WatermarkLayer.dynamicLayer);
    });

    test('uses layer-start preview resolver when no optimized ids exist', () {
      final stateView = _buildStateView();
      final previousRenderKey = _buildDynamicRenderKey(
        optimizedDynamicElementIds: const <String>{},
        dynamicLayerStartIndex: 8,
        rendersWholeElementScene: true,
        highlightMaskLayer: HighlightMaskLayer.staticLayer,
        watermarkLayer: WatermarkLayer.staticLayer,
      );
      var optimizedResolverCalled = false;
      var layerStartResolverCalled = false;
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        previousRenderKey: previousRenderKey,
        resolvePreviewByLayerStart: (view, dynamicLayerStartIndex) {
          layerStartResolverCalled = true;
          expect(dynamicLayerStartIndex, 8);
          return {'rect': _rectangle(id: 'rect')};
        },
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) {
          optimizedResolverCalled = true;
          return const <String, ElementState>{};
        },
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            previewElementsById.keys.toSet(),
      );

      expect(layerStartResolverCalled, isTrue);
      expect(optimizedResolverCalled, isFalse);
      expect(scene.previewElementsById.keys, contains('rect'));
      expect(scene.dynamicPreviewElementIds, {'rect'});
      expect(scene.optimizedDynamicElementIds, isEmpty);
      expect(scene.optimizedSceneHasPotentialOccluders, isFalse);
      expect(scene.dynamicLayerStartIndex, 8);
      expect(scene.rendersWholeElementScene, isTrue);
      expect(scene.highlightMaskLayer, HighlightMaskLayer.staticLayer);
      expect(scene.watermarkLayer, WatermarkLayer.staticLayer);
    });

    test('clears occluder hint when optimized ids are empty', () {
      final stateView = _buildStateView();
      final previousRenderKey = _buildDynamicRenderKey(
        optimizedDynamicElementIds: const <String>{},
        optimizedSceneHasPotentialOccluders: true,
        dynamicLayerStartIndex: 4,
        rendersWholeElementScene: true,
        highlightMaskLayer: HighlightMaskLayer.staticLayer,
      );

      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        previousRenderKey: previousRenderKey,
        resolvePreviewByLayerStart: (view, dynamicLayerStartIndex) =>
            const <String, ElementState>{},
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) =>
            const <String, ElementState>{},
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            const <String>{},
      );

      expect(scene.optimizedDynamicElementIds, isEmpty);
      expect(scene.optimizedSceneHasPotentialOccluders, isFalse);
    });

    test('returns immutable snapshot collections', () {
      final stateView = _buildStateView();
      final previousRenderKey = _buildDynamicRenderKey(
        optimizedDynamicElementIds: const {'rect'},
        optimizedSceneHasPotentialOccluders: true,
        dynamicLayerStartIndex: null,
        rendersWholeElementScene: false,
        highlightMaskLayer: HighlightMaskLayer.dynamicLayer,
      );
      final mutablePreviewElements = <String, ElementState>{
        'rect': _rectangle(id: 'rect'),
      };
      final mutableDynamicIds = <String>{'rect'};
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        previousRenderKey: previousRenderKey,
        resolvePreviewByLayerStart: (view, dynamicLayerStartIndex) =>
            mutablePreviewElements,
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) =>
            mutablePreviewElements,
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            mutableDynamicIds,
      );

      mutablePreviewElements['next'] = _rectangle(id: 'next');
      mutableDynamicIds.add('next');

      expect(scene.previewElementsById.keys, isNot(contains('next')));
      expect(scene.dynamicPreviewElementIds, isNot(contains('next')));
      expect(
        () => scene.previewElementsById['third'] = _rectangle(id: 'third'),
        throwsUnsupportedError,
      );
      expect(
        () => scene.dynamicPreviewElementIds.add('third'),
        throwsUnsupportedError,
      );
      expect(
        () => scene.optimizedDynamicElementIds.add('third'),
        throwsUnsupportedError,
      );
    });
  });
}

DrawStateView _buildStateView() {
  final state = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [_seedRectangle]),
    ),
  );
  return DrawStateView.withPreview(
    state: state,
    previewElementsById: const {},
    effectiveSelection: EffectiveSelection.none,
    snapGuides: const [],
  );
}

DynamicCanvasRenderKey _buildDynamicRenderKey({
  required Set<String> optimizedDynamicElementIds,
  required int? dynamicLayerStartIndex,
  required bool rendersWholeElementScene,
  required HighlightMaskLayer highlightMaskLayer,
  WatermarkLayer watermarkLayer = WatermarkLayer.none,
  bool optimizedSceneHasPotentialOccluders = false,
}) {
  final config = DrawConfig.defaultConfig;
  return DynamicCanvasRenderKey(
    creatingElement: null,
    effectiveSelection: EffectiveSelection.none,
    boxSelectionBounds: null,
    selectedIds: const <String>{},
    hoveredElementId: null,
    hoveredBindingElementId: null,
    hoveredArrowHandle: null,
    activeArrowHandle: null,
    arrowDeleteIndicatorVisible: false,
    hoverSelectionConfig: config.selection,
    snapGuides: const [],
    documentVersion: 1,
    textRenderingCacheRevision: 0,
    camera: CameraState.initial,
    previewElementsById: const <String, ElementState>{},
    optimizedDynamicElementIds: optimizedDynamicElementIds,
    optimizedSceneHasPotentialOccluders: optimizedSceneHasPotentialOccluders,
    dynamicLayerStartIndex: dynamicLayerStartIndex,
    rendersWholeElementScene: rendersWholeElementScene,
    scaleFactor: 1,
    selectionConfig: config.selection,
    boxSelectionConfig: config.boxSelection,
    snapConfig: config.snap,
    canvasConfig: config.canvas,
    gridConfig: config.grid,
    highlightMaskLayer: highlightMaskLayer,
    highlightMaskConfig: const HighlightMaskConfig(),
    watermarkLayer: watermarkLayer,
    watermarkConfig: const WatermarkConfig(),
    elementRegistry: DefaultElementRegistry(),
    performanceMonitoringEnabled: false,
  );
}

ElementState _rectangle({required String id}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

const _seedRectangle = ElementState(
  id: 'seed',
  rect: DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);
