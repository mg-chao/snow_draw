import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
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

    test('collectCoreBindableRelations includes unbound bindables '
        'with empty arrow lists', () {
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
    });
  });

  group('arrow_core_bridge document projection', () {
    test(
      'collectCoreAnchorElementIdsByBindableId includes serial text anchors',
      () {
        final serial = _serialElement(
          id: 'serial-1',
          textElementId: 'text-1',
          zIndex: 0,
        );
        final text = _textElement(id: 'text-1', zIndex: 1);

        final anchors = collectCoreAnchorElementIdsByBindableId(<ElementState>[
          serial,
          text,
        ]);

        expect(anchors['serial-1'], <String>['serial-1', 'text-1']);
        expect(anchors['text-1'], <String>['text-1']);
      },
    );

    test(
      'projectCoreDocument carries anchor lookup and ordered ids override',
      () {
        final serial = _serialElement(
          id: 'serial-1',
          textElementId: 'text-1',
          zIndex: 0,
        );
        final text = _textElement(id: 'text-1', zIndex: 1);
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 30, y: 30),
            DrawPoint(x: 130, y: 30),
          ],
          zIndex: 2,
          startBinding: const ArrowBinding(
            elementId: 'serial-1',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );
        const orderOverride = <String>['serial-1', 'text-1', 'arrow-1'];

        final projection = projectCoreDocument(<ElementState>[
          serial,
          text,
          arrow,
        ], orderedElementIds: orderOverride);

        expect(projection.orderedElementIds, orderOverride);
        expect(projection.anchorElementIdsByBindableId['serial-1'], <String>[
          'serial-1',
          'text-1',
        ]);
        expect(projection.arrows, hasLength(1));
        expect(projection.arrowSources.keys, contains('arrow-1'));
      },
    );

    test(
      'toCoreBindableState maps text corner radius to adaptive roundness',
      () {
        const text = ElementState(
          id: 'text-1',
          rect: DrawRect(minX: 100, minY: 60, maxX: 260, maxY: 140),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: TextData(text: 'rounded', cornerRadius: 14, strokeWidth: 3),
        );

        final bindable = toCoreBindableState(text);

        expect(bindable, isNotNull);
        expect(bindable!.shape, 'rectangle');
        expect(bindable.strokeWidth, 3);
        expect(bindable.roundness, isNotNull);
        expect(bindable.roundness!.type, 'adaptive');
        expect(bindable.roundness!.value, 14);
      },
    );

    test('toCoreBindableState maps highlight ellipse as ellipse bindable', () {
      const highlight = ElementState(
        id: 'highlight-1',
        rect: DrawRect(minX: 80, minY: 40, maxX: 200, maxY: 160),
        rotation: 0,
        opacity: 1,
        zIndex: 5,
        data: HighlightData(shape: HighlightShape.ellipse, strokeWidth: 2),
      );

      final bindable = toCoreBindableState(highlight);

      expect(bindable, isNotNull);
      expect(bindable!.shape, 'ellipse');
      expect(bindable.strokeWidth, 2);
      expect(bindable.zIndex, 5);
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

ElementState _serialElement({
  required String id,
  required int zIndex,
  String? textElementId,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: SerialNumberData(textElementId: textElementId),
);

ElementState _textElement({required String id, required int zIndex}) =>
    ElementState(
      id: id,
      rect: const DrawRect(minX: 100, maxX: 200, maxY: 50),
      rotation: 0,
      opacity: 1,
      zIndex: zIndex,
      data: const TextData(text: 'anchor'),
    );
