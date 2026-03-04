import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_bridge relation snapshots', () {
    test(
      'collectCoreBindableRelations includes arrow ids for bound bindables',
      () {
        final target = _rectangleElement(
          id: 'rect-1',
          rect: const DrawRect(maxX: 100, maxY: 100),
          zIndex: 0,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 20, y: 20),
            DrawPoint(x: 140, y: 20),
          ],
          zIndex: 1,
          startBinding: const ArrowBinding(
            elementId: 'rect-1',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );

        final relations = collectCoreBindableRelations(<ElementState>[
          target,
          arrow,
        ]);

        expect(relations, hasLength(1));
        expect(relations.first.id, 'rect-1');
        expect(relations.first.boundArrowIds, <String>['arrow-1']);
      },
    );

    test(
      'collectCoreBindableRelations includes unbound bindables '
      'with empty arrow lists',
      () {
        final first = _rectangleElement(
          id: 'rect-1',
          rect: const DrawRect(maxX: 100, maxY: 100),
          zIndex: 0,
        );
        final second = _rectangleElement(
          id: 'rect-2',
          rect: const DrawRect(minX: 200, maxX: 300, maxY: 100),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 20, y: 20),
            DrawPoint(x: 140, y: 20),
          ],
          zIndex: 2,
          endBinding: const ArrowBinding(
            elementId: 'rect-1',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );

        final relations = collectCoreBindableRelations(<ElementState>[
          first,
          second,
          arrow,
        ]);

        expect(relations, hasLength(2));
        expect(relations[0].id, 'rect-1');
        expect(relations[0].boundArrowIds, <String>['arrow-1']);
        expect(relations[1].id, 'rect-2');
        expect(relations[1].boundArrowIds, isEmpty);
      },
    );
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
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}
