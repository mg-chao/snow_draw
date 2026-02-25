import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_hit_tester.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  const tester = FreeDrawHitTester();

  test('hits open stroke when one rect dimension is zero', () {
    const element = ElementState(
      id: 'free_draw_zero_width',
      rect: DrawRect(minX: 20, maxX: 20, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FreeDrawData(
        points: <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 0, y: 0.5),
          DrawPoint(x: 0, y: 1),
        ],
        strokeWidth: 8,
      ),
    );

    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 20, y: 60),
    );

    expect(hit, isTrue);
  });

  test('matches rendered open spline near endpoint curvature', () {
    const element = ElementState(
      id: 'free_draw_open_curve',
      rect: DrawRect(maxX: 100, maxY: 100),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FreeDrawData(
        points: <DrawPoint>[
          DrawPoint(x: 0.28308338, y: 0.03386119),
          DrawPoint(x: 0.15126790, y: 0.95744714),
          DrawPoint(x: 0.96063709, y: 0.99990010),
          DrawPoint(x: 0.76643711, y: 0.05118744),
        ],
      ),
    );

    const samplePoint = DrawPoint(x: 23, y: 35);
    final hit = tester.hitTest(element: element, position: samplePoint);

    expect(hit, isTrue);
  });

  test('uses canonical points for hit testing', () {
    const element = ElementState(
      id: 'free_draw_baked_points',
      rect: DrawRect(maxX: 100, maxY: 100),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FreeDrawData(
        points: <DrawPoint>[DrawPoint(x: 0.5, y: 0), DrawPoint(x: 0.5, y: 1)],
        strokeWidth: 8,
      ),
    );

    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isTrue);
  });

  test('cache reuses geometry when element rect is translated', () {
    const data = FreeDrawData(
      points: <DrawPoint>[
        DrawPoint.zero,
        DrawPoint(x: 0.5, y: 0.5),
        DrawPoint(x: 1, y: 1),
      ],
      strokeWidth: 8,
    );
    const original = ElementState(
      id: 'free_draw_cache_move',
      rect: DrawRect(maxX: 100, maxY: 100),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: data,
    );
    const moved = ElementState(
      id: 'free_draw_cache_move',
      rect: DrawRect(minX: 200, minY: 120, maxX: 300, maxY: 220),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: data,
    );

    final warmupHit = tester.hitTest(
      element: original,
      position: const DrawPoint(x: 50, y: 50),
    );
    final movedHit = tester.hitTest(
      element: moved,
      position: const DrawPoint(x: 250, y: 170),
    );

    expect(warmupHit, isTrue);
    expect(movedHit, isTrue);
  });
}
