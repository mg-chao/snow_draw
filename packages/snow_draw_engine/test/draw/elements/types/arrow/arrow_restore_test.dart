import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart'
    as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_restore.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_restore restore repair integration', () {
    test('repairArrowElementsOnRestore clears dangling endpoint bindings', () {
      final bindable = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 120, maxX: 220, maxY: 120),
        zIndex: 0,
      );
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 40, y: 60),
          DrawPoint(x: 180, y: 60),
        ],
        zIndex: 1,
        startBinding: const ArrowBinding(
          elementId: 'missing-bindable',
          anchor: DrawPoint(x: 0.5, y: 0.5),
        ),
        endBinding: const ArrowBinding(
          elementId: 'rect-1',
          anchor: DrawPoint(x: 0, y: 0.5),
        ),
      );

      final repaired = repairArrowElementsOnRestore(
        elements: <ElementState>[bindable, arrow],
      );
      final repairedArrow =
          repaired.firstWhere((element) => element.id == arrow.id).data
              as ArrowData;

      expect(repairedArrow.startBinding, isNull);
      expect(repairedArrow.endBinding?.elementId, bindable.id);
    });

    test(
      'repairArrowElementsOnRestore normalizes invalid unbound elbow arrows',
      () {
        final invalidElbow = _arrowElement(
          id: 'elbow-invalid',
          points: const <DrawPoint>[
            DrawPoint(x: 20, y: 20),
            DrawPoint(x: 120, y: 70),
            DrawPoint(x: 210, y: 130),
          ],
          zIndex: 0,
          arrowType: ArrowType.elbow,
        );
        final beforeArrow = toCoreArrowState(
          element: invalidElbow,
          data: invalidElbow.data as ArrowData,
        );
        expect(core.validateElbowPoints(beforeArrow.points), isFalse);

        final repaired = repairArrowElementsOnRestore(
          elements: <ElementState>[invalidElbow],
        );
        final repairedElbow = repaired.first;
        final repairedArrow = toCoreArrowState(
          element: repairedElbow,
          data: repairedElbow.data as ArrowData,
        );

        expect(core.validateElbowPoints(repairedArrow.points), isTrue);
      },
    );
  });

  group('arrow_restore directional arrow helpers', () {
    test(
      'createDirectionalArrowWorldPoints produces rightward routed points',
      () {
        const start = DrawRect(minX: 20, minY: 40, maxX: 120, maxY: 140);
        const end = DrawRect(minX: 260, minY: 60, maxX: 360, maxY: 160);

        final points = createDirectionalArrowWorldPoints(
          startBounds: start,
          endBounds: end,
          direction: 'right',
        );

        expect(points, hasLength(2));
        expect(points.first.x, greaterThan(start.maxX));
        expect(points.last.x, lessThan(end.minX));
      },
    );

    test('createDirectionalArrowLayout returns normalized geometry', () {
      const start = DrawRect(minX: 40, minY: 80, maxX: 140, maxY: 180);
      const end = DrawRect(minX: 60, minY: 260, maxX: 160, maxY: 360);

      final layout = createDirectionalArrowLayout(
        startBounds: start,
        endBounds: end,
        direction: 'down',
      );

      expect(layout.rect.width, greaterThan(0));
      expect(layout.rect.height, greaterThan(0));
      expect(layout.normalizedPoints, hasLength(2));
      expect(layout.normalizedPoints.first, DrawPoint.zero);
      expect(layout.normalizedPoints.last.x, inInclusiveRange(0, 1));
      expect(layout.normalizedPoints.last.y, inInclusiveRange(0, 1));
    });
  });
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowType arrowType = ArrowType.straight,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      arrowType: arrowType,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}
