import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('Render task value semantics', () {
    test('element tasks compare by value', () {
      const element = ElementState(
        id: 'rect-1',
        rect: DrawRect(minX: 10, minY: 12, maxX: 90, maxY: 60),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      const first = RectangleRenderTask(
        element: element,
        data: RectangleData(),
        localeTag: 'en',
      );
      const second = RectangleRenderTask(
        element: element,
        data: RectangleData(),
        localeTag: 'en',
      );
      const differentLocale = RectangleRenderTask(
        element: element,
        data: RectangleData(),
        localeTag: 'zh-CN',
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(equals(differentLocale)));
    });

    test('overlay tasks compare list payloads by value', () {
      const handles = <ArrowPointHandle>[
        ArrowPointHandle(
          elementId: 'arrow-1',
          kind: ArrowPointKind.turning,
          index: 0,
          position: DrawPoint(x: 32, y: 48),
        ),
      ];
      const first = ArrowPointOverlayRenderTask(
        handles: handles,
        selectionConfig: SelectionConfig(),
      );
      const second = ArrowPointOverlayRenderTask(
        handles: handles,
        selectionConfig: SelectionConfig(),
      );
      const changedIndicator = ArrowPointOverlayRenderTask(
        handles: handles,
        selectionConfig: SelectionConfig(),
        deleteIndicatorVisible: true,
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(equals(changedIndicator)));
    });
  });

  group('FrameRenderPlan value semantics', () {
    test('plan compares camera, scale, locale, and ordered tasks', () {
      const baseTask = BackgroundRenderTask(color: DrawColor(0xFFFFFFFF));
      const changedTask = BackgroundRenderTask(color: DrawColor(0xFF000000));
      const first = FrameRenderPlan(
        tasks: <RenderTask>[baseTask],
        camera: CameraState.initial,
        scaleFactor: 1,
        localeTag: 'en',
      );
      const second = FrameRenderPlan(
        tasks: <RenderTask>[baseTask],
        camera: CameraState.initial,
        scaleFactor: 1,
        localeTag: 'en',
      );
      const differentTask = FrameRenderPlan(
        tasks: <RenderTask>[changedTask],
        camera: CameraState.initial,
        scaleFactor: 1,
        localeTag: 'en',
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(equals(differentTask)));
    });
  });
}
