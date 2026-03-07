import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_routing_data.dart';
import 'package:snow_draw_engine/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowData elbow routing state', () {
    test('copyWith clears elbow routing when switching away from elbow', () {
      const data = ArrowData(
        arrowType: ArrowType.elbow,
        elbowRoutingData: ElbowRoutingData(
          fixedSegments: <ElbowFixedSegment>[
            ElbowFixedSegment(
              index: 1,
              start: DrawPoint.zero,
              end: DrawPoint(x: 10, y: 0),
            ),
          ],
          startIsSpecial: true,
          endIsSpecial: true,
        ),
      );

      final next = data.copyWith(arrowType: ArrowType.straight);

      expect(next.arrowType, ArrowType.straight);
      expect(next.elbowRoutingData, isNull);
      expect(next.fixedSegments, isNull);
      expect(next.startIsSpecial, isNull);
      expect(next.endIsSpecial, isNull);
    });

    test('fromJson ignores elbow-only payload for non-elbow arrows', () {
      final data = ArrowData.fromJson(<String, dynamic>{
        'typeId': 'arrow',
        'points': const <Map<String, double>>[
          {'x': 0, 'y': 0},
          {'x': 1, 'y': 1},
        ],
        'color': 0xFF000000,
        'strokeWidth': 2.0,
        'strokeStyle': StrokeStyle.solid.name,
        'arrowType': ArrowType.straight.name,
        'startArrowhead': ArrowheadStyle.none.name,
        'endArrowhead': ArrowheadStyle.standard.name,
        'fixedSegments': const <Map<String, dynamic>>[
          {
            'index': 1,
            'start': {'x': 0, 'y': 0},
            'end': {'x': 10, 'y': 0},
          },
        ],
        'startIsSpecial': true,
        'endIsSpecial': true,
      });

      expect(data.arrowType, ArrowType.straight);
      expect(data.elbowRoutingData, isNull);
      expect(data.fixedSegments, isNull);
    });
  });

  group('LineData elbow routing cleanup', () {
    test('toJson omits elbow-only fields', () {
      final json = const LineData().toJson();

      expect(json.containsKey('fixedSegments'), isFalse);
      expect(json.containsKey('startIsSpecial'), isFalse);
      expect(json.containsKey('endIsSpecial'), isFalse);
    });
  });
}
