import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_session.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowCoreSession', () {
    test('fromElements builds projection and normalized context', () {
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 10, y: 10),
          DrawPoint(x: 110, y: 10),
        ],
        zIndex: 0,
      );

      final session = ArrowCoreSession.fromElements(
        <ElementState>[arrow],
        zoom: 2,
        isBindingEnabled: false,
        bindMode: core.bindModeInside,
        maxCoordinate: 1234,
      );

      expect(session.hasArrows, isTrue);
      expect(session.arrows, hasLength(1));
      expect(session.context.zoom, 2);
      expect(session.context.isBindingEnabled, isFalse);
      expect(session.context.bindMode, core.bindModeInside);
      expect(session.context.maxCoordinate, 1234);
    });

    test('applyArrowPatches maps core patches onto source elements', () {
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[DrawPoint.zero, DrawPoint(x: 100, y: 0)],
        zIndex: 0,
      );

      final session = ArrowCoreSession.fromElements(<ElementState>[arrow]);
      final updates = session.applyArrowPatches(<core.ArrowStatePatchWithId>[
        const core.ArrowStatePatchWithId(
          id: 'arrow-1',
          patch: <String, dynamic>{
            'width': 200.0,
            'height': 0.0,
            'points': <core.Point>[
              <double>[0, 0],
              <double>[200, 0],
            ],
          },
        ),
        const core.ArrowStatePatchWithId(
          id: 'unknown-arrow',
          patch: <String, dynamic>{'width': 999.0},
        ),
      ]);

      expect(updates.keys, <String>['arrow-1']);
      final updatedArrow = updates['arrow-1']!;
      expect(updatedArrow.rect.width, closeTo(200, 1e-6));
      expect(updatedArrow.rect.minX, closeTo(0, 1e-6));
    });

    test('reduceEventsToOrderedElementIds supports anchor ordering', () {
      final serial = _serialElement(id: 'serial-1', textElementId: 'text-1');
      final text = _textElement(id: 'text-1');
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 140, y: 20),
        ],
        zIndex: 2,
        startBinding: const ArrowBinding(
          elementId: 'serial-1',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
      );

      final session = ArrowCoreSession.fromElements(
        <ElementState>[serial, text, arrow],
        orderedElementIds: const <String>['arrow-1', 'serial-1', 'text-1'],
      );
      final ordered = session.reduceEventsToOrderedElementIds(
        const <core.ArrowEngineEvent>[
          core.ReorderArrowEvent(arrowId: 'arrow-1', bindableId: 'serial-1'),
        ],
      );

      expect(ordered, <String>['serial-1', 'arrow-1', 'text-1']);
    });
  });
}

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowBinding? startBinding,
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
    data: ArrowData(points: normalized, startBinding: startBinding),
  );
}

ElementState _serialElement({
  required String id,
  required String textElementId,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: SerialNumberData(textElementId: textElementId),
);

ElementState _textElement({required String id}) => ElementState(
  id: id,
  rect: const DrawRect(minX: 100, maxX: 200, maxY: 50),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: const TextData(text: 'anchor'),
);
