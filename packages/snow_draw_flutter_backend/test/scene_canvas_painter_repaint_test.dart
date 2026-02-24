import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

void main() {
  test('does not repaint when render key is unchanged', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final initialView = DrawStateView.fromState(DrawState());
    final nextView = DrawStateView.fromState(DrawState());

    final key = SceneCanvasRenderKey(
      documentElementsVersion: 0,
      creatingElement: null,
      textRenderingCacheRevision: 0,
      previewElementsById: const <String, ElementState>{},
      elementRegistry: registry,
      performanceMonitoringEnabled: false,
      framePlan: FrameRenderPlan.empty,
    );

    final previousPainter = SceneCanvasPainter(
      renderKey: key,
      stateView: initialView,
    );
    final nextPainter = SceneCanvasPainter(renderKey: key, stateView: nextView);

    expect(nextPainter.shouldRepaint(previousPainter), isFalse);
  });

  test('repaints when render key changes', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final view = DrawStateView.fromState(DrawState());
    final previousPainter = SceneCanvasPainter(
      renderKey: SceneCanvasRenderKey(
        documentElementsVersion: 0,
        creatingElement: null,
        textRenderingCacheRevision: 0,
        previewElementsById: const <String, ElementState>{},
        elementRegistry: registry,
        performanceMonitoringEnabled: false,
        framePlan: FrameRenderPlan.empty,
      ),
      stateView: view,
    );
    final nextPainter = SceneCanvasPainter(
      renderKey: SceneCanvasRenderKey(
        documentElementsVersion: 1,
        creatingElement: null,
        textRenderingCacheRevision: 0,
        previewElementsById: const <String, ElementState>{},
        elementRegistry: registry,
        performanceMonitoringEnabled: false,
        framePlan: FrameRenderPlan.empty,
      ),
      stateView: view,
    );

    expect(nextPainter.shouldRepaint(previousPainter), isTrue);
  });
}
