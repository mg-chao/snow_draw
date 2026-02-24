import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

void main() {
  test(
    'repaints when scene content fingerprint changes after style updates',
    () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);

      const baseElement = ElementState(
        id: 'rect-1',
        rect: DrawRect(maxX: 100, maxY: 80),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final styledElement = baseElement.copyWith(
        data: (baseElement.data as RectangleData).copyWith(
          color: const DrawColor(0xFFFF0000),
        ),
      );

      final initialState = DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [baseElement]),
        ),
      );
      final updatedDocument = initialState.domain.document.copyWith(
        elements: [styledElement],
      );
      final updatedState = initialState.copyWith(
        domain: initialState.domain.copyWith(document: updatedDocument),
      );

      final initialView = DrawStateView.fromState(initialState);
      final updatedView = DrawStateView.fromState(updatedState);

      final beforeKey = SceneCanvasRenderKey(
        creatingElement: null,
        documentElementsVersion: initialState.domain.document.elementsVersion,
        textRenderingCacheRevision: 0,
        previewElementsById: const <String, ElementState>{},
        elementRegistry: registry,
        performanceMonitoringEnabled: false,
        framePlan: FrameRenderPlan.empty,
      );
      final afterKey = SceneCanvasRenderKey(
        creatingElement: null,
        documentElementsVersion: updatedDocument.elementsVersion,
        textRenderingCacheRevision: 0,
        previewElementsById: const <String, ElementState>{},
        elementRegistry: registry,
        performanceMonitoringEnabled: false,
        framePlan: FrameRenderPlan.empty,
      );

      final previousPainter = SceneCanvasPainter(
        renderKey: beforeKey,
        stateView: initialView,
      );
      final nextPainter = SceneCanvasPainter(
        renderKey: afterKey,
        stateView: updatedView,
      );

      expect(afterKey, isNot(beforeKey));
      expect(nextPainter.shouldRepaint(previousPainter), isTrue);
    },
  );
}
