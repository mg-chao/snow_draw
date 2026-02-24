import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/render_keys.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/scene_canvas_painter.dart';

void main() {
  test('repaints when state view identity changes', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final initialView = DrawStateView.fromState(DrawState());
    final nextView = DrawStateView.fromState(DrawState());

    final key = SceneCanvasRenderKey(
      creatingElement: null,
      textRenderingCacheRevision: 0,
      previewElementsById: const <String, ElementState>{},
      elementRegistry: registry,
      performanceMonitoringEnabled: false,
      framePlan: const FrameRenderPlan(
        tasks: <FrameRenderTask>[],
        camera: CameraState.initial,
        scaleFactor: 1,
      ),
    );

    final previousPainter = SceneCanvasPainter(
      renderKey: key,
      stateView: initialView,
    );
    final nextPainter = SceneCanvasPainter(renderKey: key, stateView: nextView);

    expect(nextPainter.shouldRepaint(previousPainter), isTrue);
  });
}
