import 'package:snow_draw_engine/draw/elements/types/connector/connector_geometry.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectorGeometry core elbow integration', () {
    test('generateElbowPathData returns rounded-corner path commands', () {
      final path = ConnectorGeometry.generateElbowPathData(
        points: const <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 100, y: 0),
          DrawPoint(x: 100, y: 100),
        ],
      );

      expect(path, 'M 0 0 L 84 0 Q 100 0, 100 16 L 100 100');
    });

    test('resolveElbowPathCommands returns typed rounded segments', () {
      final commands = ConnectorGeometry.resolveElbowPathCommands(
        points: const <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 100, y: 0),
          DrawPoint(x: 100, y: 100),
        ],
      );

      expect(commands, hasLength(4));
      expect(commands[0], isA<ConnectorPathMoveCommand>());
      expect(commands[1], isA<ConnectorPathLineCommand>());
      expect(commands[2], isA<ConnectorPathQuadraticCommand>());
      expect(commands[3], isA<ConnectorPathLineCommand>());

      expect((commands[0] as ConnectorPathMoveCommand).point, DrawPoint.zero);
      expect(
        (commands[1] as ConnectorPathLineCommand).point,
        const DrawPoint(x: 84, y: 0),
      );
      final curve = commands[2] as ConnectorPathQuadraticCommand;
      expect(curve.controlPoint, const DrawPoint(x: 100, y: 0));
      expect(curve.point, const DrawPoint(x: 100, y: 16));
      expect(
        (commands[3] as ConnectorPathLineCommand).point,
        const DrawPoint(x: 100, y: 100),
      );
    });

    test('generateElbowPathData handles a single point', () {
      final path = ConnectorGeometry.generateElbowPathData(
        points: const <DrawPoint>[DrawPoint(x: 12.5, y: -3.25)],
      );

      expect(path, 'M 12.5 -3.25');
    });

    test(
      'resolveElbowPathCommands falls back to a move command for one point',
      () {
        final commands = ConnectorGeometry.resolveElbowPathCommands(
          points: const <DrawPoint>[DrawPoint(x: 12.5, y: -3.25)],
        );

        expect(commands, hasLength(1));
        expect(commands.single, isA<ConnectorPathMoveCommand>());
        expect(
          (commands.single as ConnectorPathMoveCommand).point,
          const DrawPoint(x: 12.5, y: -3.25),
        );
      },
    );
  });
}
