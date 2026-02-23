import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';

void main() {
  group('SceneCanvasRenderKey', () {
    test('delete indicator visibility participates in equality', () {
      final registry = DefaultElementRegistry();
      final hidden = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final visible = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: true,
      );

      expect(hidden, isNot(visible));
      expect(hidden.hashCode, isNot(visible.hashCode));
    });

    test('creating element revision participates in equality', () {
      final registry = DefaultElementRegistry();
      final first = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        creatingElement: _creatingElementSnapshot(revision: 1),
      );
      final second = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        creatingElement: _creatingElementSnapshot(revision: 2),
      );

      expect(first, isNot(second));
      expect(first.hashCode, isNot(second.hashCode));
    });

    test('preview revision participates with map-identity fast path', () {
      final registry = DefaultElementRegistry();
      final sharedPreviewMap = <String, ElementState>{};
      final first = _buildCanvasRenderKey(
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
      final second = _buildCanvasRenderKey(
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
      final first = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: <String, ElementState>{},
        previewElementsRevision: 9,
      );
      final second = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        previewElementsById: <String, ElementState>{},
        previewElementsRevision: 9,
      );

      expect(first, isNot(second));
    });

    test('volatile preview hint does not affect equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final hinted = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        volatilePreviewElementIds: {'line-1'},
      );

      expect(baseline, hinted);
      expect(baseline.hashCode, hinted.hashCode);
    });

    test('watermark config participates in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
      );
      final changedWatermark = _buildCanvasRenderKey(
        registry: registry,
        arrowDeleteIndicatorVisible: false,
        watermarkConfig: const WatermarkConfig(text: 'CONFIDENTIAL'),
      );

      expect(baseline, isNot(changedWatermark));
      expect(baseline.hashCode, isNot(changedWatermark.hashCode));
    });
  });
}

SceneCanvasRenderKey _buildCanvasRenderKey({
  required DefaultElementRegistry registry,
  required bool arrowDeleteIndicatorVisible,
  CreatingElementSnapshot? creatingElement,
  Map<String, ElementState> previewElementsById = const {},
  int? previewElementsRevision,
  Set<String>? volatilePreviewElementIds,
  WatermarkConfig? watermarkConfig,
}) => SceneCanvasRenderKey(
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
  volatilePreviewElementIds: volatilePreviewElementIds,
  scaleFactor: 1,
  selectionConfig: const SelectionConfig(),
  boxSelectionConfig: const BoxSelectionConfig(),
  snapConfig: const SnapConfig(),
  canvasConfig: const CanvasConfig(),
  gridConfig: const GridConfig(),
  isHighlightMaskVisible: false,
  highlightMaskConfig: const HighlightMaskConfig(),
  isWatermarkVisible: false,
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
