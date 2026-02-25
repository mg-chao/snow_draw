import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('FreeDrawData', () {
    test('JSON payload contains only canonical points field', () {
      const data = FreeDrawData();
      final json = data.toJson();

      expect(
        json.keys.toSet(),
        equals(<String>{
          'typeId',
          'points',
          'color',
          'fillColor',
          'strokeWidth',
          'strokeStyle',
          'fillStyle',
        }),
      );
    });

    test('roundtrips canonical points payload', () {
      const data = FreeDrawData(
        points: <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 0.5, y: 0.5),
          DrawPoint(x: 1, y: 1),
        ],
      );

      final encoded = data.toJson();
      final decoded = FreeDrawData.fromJson(encoded);

      expect(decoded.toJson(), equals(encoded));
      expect(decoded.points, equals(data.points));
    });
  });
}
