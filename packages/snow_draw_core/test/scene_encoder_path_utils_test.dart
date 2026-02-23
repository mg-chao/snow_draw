import 'package:snow_draw_core/draw/elements/types/shared/scene_encoder_path_utils.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('closeRenderPathIfNeeded', () {
    test('appends close command for open paths', () {
      const path = RenderPath(<RenderPathCommand>[
        RenderMoveTo(DrawPoint.zero),
        RenderLineTo(DrawPoint(x: 1, y: 0)),
      ]);

      final resolved = closeRenderPathIfNeeded(path);

      expect(resolved.commands, hasLength(3));
      expect(resolved.commands.last, isA<RenderClosePath>());
    });

    test('reuses input path when already closed', () {
      const path = RenderPath(<RenderPathCommand>[
        RenderMoveTo(DrawPoint.zero),
        RenderLineTo(DrawPoint(x: 1, y: 0)),
        RenderClosePath(),
      ]);

      final resolved = closeRenderPathIfNeeded(path);

      expect(identical(resolved, path), isTrue);
    });
  });

  group('clampRoundedRectCornerRadius', () {
    test('clamps negative values and oversized radii', () {
      expect(
        clampRoundedRectCornerRadius(cornerRadius: -1, width: 10, height: 6),
        0,
      );
      expect(
        clampRoundedRectCornerRadius(cornerRadius: 99, width: 10, height: 6),
        3,
      );
    });
  });

  group('buildPolylineRenderPath', () {
    test('returns empty path when there are fewer than two points', () {
      final path = buildPolylineRenderPath(const <DrawPoint>[DrawPoint.zero]);
      expect(path.commands, isEmpty);
    });

    test('builds move and line commands for all points', () {
      final path = buildPolylineRenderPath(const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 10, y: 0),
        DrawPoint(x: 10, y: 5),
      ]);

      expect(path.commands, hasLength(3));
      expect(path.commands[0], isA<RenderMoveTo>());
      expect(path.commands[1], isA<RenderLineTo>());
      expect(path.commands[2], isA<RenderLineTo>());
    });
  });

  group('buildCatmullRomRenderPath', () {
    test('falls back to polyline path when fewer than three points', () {
      final path = buildCatmullRomRenderPath(const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 10, y: 0),
      ]);

      expect(path.commands, hasLength(2));
      expect(path.commands[0], isA<RenderMoveTo>());
      expect(path.commands[1], isA<RenderLineTo>());
    });

    test('builds cubic commands for multi-point curves', () {
      final path = buildCatmullRomRenderPath(const <DrawPoint>[
        DrawPoint(x: 0, y: 0),
        DrawPoint(x: 10, y: 0),
        DrawPoint(x: 20, y: 10),
      ]);

      expect(path.commands, hasLength(3));
      expect(path.commands[0], isA<RenderMoveTo>());
      expect(path.commands[1], isA<RenderCubicTo>());
      expect(path.commands[2], isA<RenderCubicTo>());
    });
  });

  test(
    'buildCenteredRoundedRectPath reuses rectangle commands for zero radius',
    () {
      const rect = DrawRect(minX: 10, minY: 20, maxX: 18, maxY: 26);

      final path = buildCenteredRoundedRectPath(rect: rect, cornerRadius: 0);

      expect(path.commands, hasLength(5));
      final moveTo = path.commands.first as RenderMoveTo;
      expect(moveTo.point.x, -4);
      expect(moveTo.point.y, -3);
      expect(path.commands.last, isA<RenderClosePath>());
    },
  );
}
