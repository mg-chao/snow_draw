import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_scene_encoder.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_scene_encoder.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/render/scene/render_scene.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('LineSceneEncoder', () {
    const encoder = LineSceneEncoder();

    test('encodes dotted stroke as round-cap dash pattern', () {
      const element = ElementState(
        id: 'line',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0.12,
        opacity: 1,
        zIndex: 0,
        data: LineData(
          points: <DrawPoint>[
            DrawPoint(x: 0, y: 0.5),
            DrawPoint(x: 0.35, y: 0.1),
            DrawPoint(x: 0.65, y: 0.9),
            DrawPoint(x: 1, y: 0.45),
          ],
          color: DrawColor(0xFF203040),
          strokeStyle: StrokeStyle.dotted,
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final local =
          transformed.child.primitives.single as RenderPathStrokePrimitive;

      expect(local.dashPattern, isNotNull);
      expect(local.strokeCap, RenderStrokeCap.round);
    });

    test('encodes patterned line fills as hatch primitives', () {
      const element = ElementState(
        id: 'line',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: LineData(
          points: <DrawPoint>[
            DrawPoint.zero,
            DrawPoint(x: 1, y: 0),
            DrawPoint(x: 1, y: 1),
            DrawPoint.zero,
          ],
          fillColor: DrawColor(0x44000000),
          fillStyle: FillStyle.line,
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;
      final hatch = localPrimitives
          .whereType<RenderHatchPathFillPrimitive>()
          .single;

      expect(hatch.pattern, RenderHatchPattern.line);
      expect(hatch.spacing, greaterThan(0));
      expect(hatch.lineWidth, greaterThan(0));
    });
  });

  group('RectangleSceneEncoder', () {
    const encoder = RectangleSceneEncoder();

    test('encodes dotted stroke as round-cap dash pattern', () {
      const element = ElementState(
        id: 'rectangle',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0.05,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(
          color: DrawColor(0xFF223344),
          strokeStyle: StrokeStyle.dotted,
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final local =
          transformed.child.primitives.single as RenderPathStrokePrimitive;

      expect(local.dashPattern, isNotNull);
      expect(local.strokeCap, RenderStrokeCap.round);
    });

    test('encodes patterned rectangle fills as hatch primitives', () {
      const element = ElementState(
        id: 'rectangle',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(
          fillColor: DrawColor(0x44000000),
          fillStyle: FillStyle.crossLine,
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;
      final hatch = localPrimitives
          .whereType<RenderHatchPathFillPrimitive>()
          .single;

      expect(hatch.pattern, RenderHatchPattern.crossLine);
      expect(hatch.spacing, greaterThan(0));
      expect(hatch.lineWidth, greaterThan(0));
    });
  });
}
