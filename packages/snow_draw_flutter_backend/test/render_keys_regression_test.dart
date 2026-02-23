import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';

void main() {
  group('SceneCanvasRenderKey', () {
    test('frame plan differences participate in equality', () {
      final registry = DefaultElementRegistry();
      final hidden = _buildCanvasRenderKey(
        registry: registry,
        framePlan: _arrowOverlayFramePlan(deleteIndicatorVisible: false),
      );
      final visible = _buildCanvasRenderKey(
        registry: registry,
        framePlan: _arrowOverlayFramePlan(deleteIndicatorVisible: true),
      );

      expect(hidden, isNot(visible));
      expect(hidden.hashCode, isNot(visible.hashCode));
    });

    test('creating element revision participates in equality', () {
      final registry = DefaultElementRegistry();
      final first = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
        creatingElement: _creatingElementSnapshot(revision: 1),
      );
      final second = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
        creatingElement: _creatingElementSnapshot(revision: 2),
      );

      expect(first, isNot(second));
      expect(first.hashCode, isNot(second.hashCode));
    });

    test('preview map content participates in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
      );
      final withPreview = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
        previewElementsById: const {
          'line-1': ElementState(
            id: 'line-1',
            rect: DrawRect(maxX: 20, maxY: 20),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: LineData(),
          ),
        },
      );

      expect(baseline, isNot(withPreview));
      expect(baseline.hashCode, isNot(withPreview.hashCode));
    });

    test('captures preview map snapshot to avoid mutable-key regressions', () {
      final registry = DefaultElementRegistry();
      final mutablePreview = <String, ElementState>{
        'line-1': const ElementState(
          id: 'line-1',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: LineData(),
        ),
      };

      final firstKey = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
        previewElementsById: mutablePreview,
      );
      mutablePreview['line-2'] = const ElementState(
        id: 'line-2',
        rect: DrawRect(maxX: 24, maxY: 24),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: LineData(),
      );
      final secondKey = _buildCanvasRenderKey(
        registry: registry,
        framePlan: FrameRenderPlan.empty,
        previewElementsById: mutablePreview,
      );

      expect(firstKey.previewElementsById.containsKey('line-2'), isFalse);
      expect(firstKey, isNot(secondKey));
      expect(firstKey.hashCode, isNot(secondKey.hashCode));
    });

    test('watermark task differences participate in equality', () {
      final registry = DefaultElementRegistry();
      final baseline = _buildCanvasRenderKey(
        registry: registry,
        framePlan: _watermarkFramePlan(const WatermarkConfig()),
      );
      final changedWatermark = _buildCanvasRenderKey(
        registry: registry,
        framePlan: _watermarkFramePlan(
          const WatermarkConfig(text: 'CONFIDENTIAL'),
        ),
      );

      expect(baseline, isNot(changedWatermark));
      expect(baseline.hashCode, isNot(changedWatermark.hashCode));
    });
  });
}

SceneCanvasRenderKey _buildCanvasRenderKey({
  required DefaultElementRegistry registry,
  required FrameRenderPlan framePlan,
  CreatingElementSnapshot? creatingElement,
  Map<String, ElementState> previewElementsById = const {},
}) => SceneCanvasRenderKey(
  creatingElement: creatingElement,
  documentVersion: 1,
  textRenderingCacheRevision: 0,
  previewElementsById: previewElementsById,
  preferFastFilterFallback: false,
  elementRegistry: registry,
  performanceMonitoringEnabled: false,
  framePlan: framePlan,
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

FrameRenderPlan _arrowOverlayFramePlan({
  required bool deleteIndicatorVisible,
}) => FrameRenderPlan(
  tasks: <RenderTask>[
    ArrowPointOverlayRenderTask(
      handles: const <ArrowPointHandle>[
        ArrowPointHandle(
          elementId: 'arrow-1',
          kind: ArrowPointKind.turning,
          index: 0,
          position: DrawPoint(x: 12, y: 16),
        ),
      ],
      selectionConfig: const SelectionConfig(),
      deleteIndicatorVisible: deleteIndicatorVisible,
    ),
  ],
  camera: CameraState.initial,
  scaleFactor: 1,
);

FrameRenderPlan _watermarkFramePlan(WatermarkConfig config) => FrameRenderPlan(
  tasks: <RenderTask>[WatermarkRenderTask(config: config)],
  camera: CameraState.initial,
  scaleFactor: 1,
);
