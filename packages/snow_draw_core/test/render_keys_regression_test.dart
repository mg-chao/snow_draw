import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_visibility.dart';
import 'package:snow_draw_core/ui/canvas/render_keys.dart';

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
  });
}

DynamicCanvasRenderKey _buildDynamicRenderKey({
  required DefaultElementRegistry registry,
  required bool arrowDeleteIndicatorVisible,
  CreatingElementSnapshot? creatingElement,
  Set<String> optimizedDynamicElementIds = const <String>{},
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
  previewElementsById: const {},
  optimizedDynamicElementIds: optimizedDynamicElementIds,
  dynamicLayerStartIndex: null,
  rendersWholeElementScene: false,
  scaleFactor: 1,
  selectionConfig: const SelectionConfig(),
  boxSelectionConfig: const BoxSelectionConfig(),
  snapConfig: const SnapConfig(),
  highlightMaskLayer: HighlightMaskLayer.none,
  highlightMaskConfig: const HighlightMaskConfig(),
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
