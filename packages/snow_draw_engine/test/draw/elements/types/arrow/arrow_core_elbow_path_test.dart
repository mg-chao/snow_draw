import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_elbow_path parser', () {
    test('parses move/line/quadratic commands', () {
      const pathData = 'M 0 0 L 10 0 Q 10 5, 15 5 L 20 5';

      final commands = parseArrowCoreElbowPathCommands(pathData);

      expect(commands, isNotNull);
      expect(commands, hasLength(4));
      expect(commands![0], isA<ArrowCoreElbowMoveTo>());
      expect(commands[1], isA<ArrowCoreElbowLineTo>());
      expect(commands[2], isA<ArrowCoreElbowQuadraticTo>());
      expect(commands[3], isA<ArrowCoreElbowLineTo>());

      final move = commands[0] as ArrowCoreElbowMoveTo;
      final quad = commands[2] as ArrowCoreElbowQuadraticTo;
      expect(move.point, DrawPoint.zero);
      expect(quad.control, const DrawPoint(x: 10, y: 5));
      expect(quad.end, const DrawPoint(x: 15, y: 5));
    });

    test('returns empty list for empty path', () {
      final commands = parseArrowCoreElbowPathCommands('   ');

      expect(commands, isEmpty);
    });

    test('returns null for malformed payload', () {
      final malformed = parseArrowCoreElbowPathCommands('M 0 0 Q 10');
      final unknown = parseArrowCoreElbowPathCommands('M 0 0 C 1 2 3 4');

      expect(malformed, isNull);
      expect(unknown, isNull);
    });
  });
}
