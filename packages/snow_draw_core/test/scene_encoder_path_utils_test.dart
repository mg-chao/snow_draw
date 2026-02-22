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
