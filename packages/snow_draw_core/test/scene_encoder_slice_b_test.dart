import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_scene_encoder.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_scene_encoder.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/render/scene/render_scene.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('ArrowSceneEncoder', () {
    const encoder = ArrowSceneEncoder();

    test(
      'encodes dashed shaft and solid arrowheads as separate primitives',
      () {
        const element = ElementState(
          id: 'arrow',
          rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: ArrowData(strokeStyle: StrokeStyle.dashed),
        );

        final scene = encoder.encodeScene(element: element);
        final transformed = scene.primitives.single as RenderTransformPrimitive;
        final localPrimitives = transformed.child.primitives;

        expect(localPrimitives, hasLength(2));
        expect(localPrimitives.first, isA<RenderPathStrokePrimitive>());
        expect(localPrimitives.last, isA<RenderPathStrokePrimitive>());
        final shaft = localPrimitives.first as RenderPathStrokePrimitive;
        final heads = localPrimitives.last as RenderPathStrokePrimitive;
        expect(shaft.dashPattern, isNotNull);
        expect(heads.dashPattern, isNull);
      },
    );

    test('encodes curved shaft using cubic path commands', () {
      const element = ElementState(
        id: 'arrow',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: ArrowData(
          arrowType: ArrowType.curved,
          points: <DrawPoint>[
            DrawPoint(x: 0, y: 0.5),
            DrawPoint(x: 0.35, y: 0.1),
            DrawPoint(x: 0.65, y: 0.9),
            DrawPoint(x: 1, y: 0.45),
          ],
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;

      expect(localPrimitives, hasLength(2));
      final shaft = localPrimitives.first as RenderPathStrokePrimitive;
      expect(shaft.path.commands.whereType<RenderCubicTo>(), isNotEmpty);
    });
  });

  group('FreeDrawSceneEncoder', () {
    const encoder = FreeDrawSceneEncoder();

    test('encodes supported free-draw stroke to path primitives', () {
      const element = ElementState(
        id: 'free',
        rect: DrawRect(maxX: 300, maxY: 200),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(
          points: <DrawPoint>[
            DrawPoint.zero,
            DrawPoint(x: 0.2, y: 0.8),
            DrawPoint(x: 0.4, y: 0.1),
            DrawPoint(x: 0.8, y: 0.9),
            DrawPoint(x: 1, y: 0.3),
          ],
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;

      expect(localPrimitives, hasLength(1));
      expect(localPrimitives.first, isA<RenderPathStrokePrimitive>());
      final stroke = localPrimitives.first as RenderPathStrokePrimitive;
      expect(stroke.path.commands, isNotEmpty);
    });

    test('encodes dotted stroke as a round-cap dash pattern', () {
      const element = ElementState(
        id: 'free',
        rect: DrawRect(maxX: 300, maxY: 200),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(
          strokeStyle: StrokeStyle.dotted,
          points: <DrawPoint>[
            DrawPoint.zero,
            DrawPoint(x: 0.25, y: 0.75),
            DrawPoint(x: 0.5, y: 0.2),
            DrawPoint(x: 0.75, y: 0.85),
            DrawPoint(x: 1, y: 0.4),
          ],
        ),
      );

      final scene = encoder.encodeScene(element: element);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;

      expect(localPrimitives, hasLength(1));
      final stroke = localPrimitives.single as RenderPathStrokePrimitive;
      expect(stroke.dashPattern, isNotNull);
      expect(stroke.strokeCap, RenderStrokeCap.round);
    });

    test('encodes patterned fill as hatch primitive', () {
      const element = ElementState(
        id: 'free',
        rect: DrawRect(maxX: 300, maxY: 200),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(
          fillColor: DrawColor(0x44000000),
          fillStyle: FillStyle.crossLine,
          points: <DrawPoint>[
            DrawPoint.zero,
            DrawPoint(x: 0.2, y: 0.8),
            DrawPoint(x: 0.4, y: 0.1),
            DrawPoint(x: 0.8, y: 0.9),
            DrawPoint.zero,
          ],
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
