import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/highlight_mask_visibility.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/watermark_visibility.dart';

void main() {
  group('DynamicCanvasRenderKey', () {
    test('delete indicator visibility participates in equality', () {
      final registry = DefaultElementRegistry();
      final hidden = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final visible = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: true,
      );

      expect(hidden, isNot(visible));
      expect(hidden.hashCode, isNot(visible.hashCode));
    });

    test('creating element revision participates in equality', () {
      final registry = DefaultElementRegistry();
      final first = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        creatingElement: _creatingElementSnapshot(revision: 1),
      );
      final second = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        creatingElement: _creatingElementSnapshot(revision: 2),
      );

      expect(first, isNot(second));
      expect(first.hashCode, isNot(second.hashCode));
    });

    test('optimized dynamic ids participate in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final optimized = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        optimizedDynamicElementIds: {'line-1'},
      );

      expect(baseline, isNot(optimized));
      expect(baseline.hashCode, isNot(optimized.hashCode));
    });

    test('optimized occluder hint participates in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        optimizedDynamicElementIds: {'line-1'},
      );
      final withOccluders = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        optimizedDynamicElementIds: {'line-1'},
        optimizedSceneHasPotentialOccluders: true,
      );

      expect(baseline, isNot(withOccluders));
      expect(baseline.hashCode, isNot(withOccluders.hashCode));
    });

    test('preview revision participates with map-identity fast path', () {
      final registry = DefaultElementRegistry();
      final sharedPreviewMap = <String, ElementState>{};
      final first = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: sharedPreviewMap,
        previewElementsRevision: 1,
      );
      sharedPreviewMap['preview-1'] = const ElementState(
        id: 'preview-1',
        rect: DrawRect(maxX: 20, maxY: 20),
        rotation: 0,
        opacity: 0.5,
        zIndex: 0,
        data: FreeDrawData(),
      );
      final second = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: sharedPreviewMap,
        previewElementsRevision: 2,
      );

      expect(first, isNot(second));
      expect(first.hashCode, isNot(second.hashCode));
    });

    test('preview revision requires identical preview map identity', () {
      final registry = DefaultElementRegistry();
      final first = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: <String, ElementState>{},
        previewElementsRevision: 9,
      );
      final second = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: <String, ElementState>{},
        previewElementsRevision: 9,
      );

      expect(first, isNot(second));
    });

    test('dynamic preview hint does not affect equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final hinted = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        dynamicPreviewElementIds: {'line-1'},
      );

      expect(baseline, hinted);
      expect(baseline.hashCode, hinted.hashCode);
    });

    test('watermark config participates in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final changedWatermark = _buildDynamicRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        watermarkConfig: const WatermarkConfig(text: 'CONFIDENTIAL'),
      );

      expect(baseline, isNot(changedWatermark));
      expect(baseline.hashCode, isNot(changedWatermark.hashCode));
    });
  });
}

DynamicCanvasRenderKey _buildDynamicRenderKey({
  required DefaultElementRegistry registry,
  required bool arrowDeleteIndicatorVisible,
  CreatingElementSnapshot? creatingElement,
  Set<String> optimizedDynamicElementIds = const <String>{},
  Map<String, ElementState> previewElementsById = const {},
  int? previewElementsRevision,
  Set<String>? dynamicPreviewElementIds,
  bool optimizedSceneHasPotentialOccluders = false,
  WatermarkConfig? watermarkConfig,
}) => DynamicCanvasRenderKey(
  creatingElement: creatingElement,
  effectiveSelection: EffectiveSelection.none,
  boxSelectionBounds: null,
  selectedIds: const <String>{},
  hoveredElementId: null,
  hoveredBindingElementId: null,
  hoveredArrowHandle: null,
  activeArrowHandle: null,
  arrowDeleteIndicatorVisible: arrowDeleteIndicatorVisible,
  hoverSelectionConfig: const SelectionConfig(),
  snapGuides: const [],
  documentVersion: 1,
  textRenderingCacheRevision: 0,
  camera: CameraState.initial,
  previewElementsById: previewElementsById,
  previewElementsRevision: previewElementsRevision,
  dynamicPreviewElementIds: dynamicPreviewElementIds,
  optimizedDynamicElementIds: optimizedDynamicElementIds,
  optimizedSceneHasPotentialOccluders: optimizedSceneHasPotentialOccluders,
  dynamicLayerStartIndex: null,
  rendersWholeElementScene: false,
  scaleFactor: 1,
  selectionConfig: const SelectionConfig(),
  boxSelectionConfig: const BoxSelectionConfig(),
  snapConfig: const SnapConfig(),
  highlightMaskLayer: HighlightMaskLayer.none,
  highlightMaskConfig: const HighlightMaskConfig(),
  watermarkLayer: WatermarkLayer.none,
  watermarkConfig: watermarkConfig ?? const WatermarkConfig(),
  elementRegistry: registry,
  performanceMonitoringEnabled: false,
);

CreatingElementSnapshot _creatingElementSnapshot({required int revision}) =>
    CreatingElementSnapshot(
      element: const ElementState(
        id: 'creating-element',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(),
      ),
      currentRect: const DrawRect(maxX: 10, maxY: 10),
      creationRevision: revision,
    );
