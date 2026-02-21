import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_scene_encoder.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_scene_encoder.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/render/scene/render_scene.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('TextSceneEncoder', () {
    const encoder = TextSceneEncoder();

    test('encodes fill-only text as a text primitive', () {
      const element = ElementState(
        id: 'text',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0.2,
        opacity: 1,
        zIndex: 0,
        data: TextData(
          text: 'Scene',
          color: DrawColor(0xFF112233),
          horizontalAlign: TextHorizontalAlign.center,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final local =
          transformed.child.primitives.single as RenderTextRunPrimitive;

      expect(local.text, 'Scene');
      expect(local.align, RenderTextAlign.center);
      expect(local.maxWidth, 200);
    });

    test('encodes text stroke via text-run stroke parameters', () {
      const element = ElementState(
        id: 'text',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(
          text: 'Scene',
          strokeColor: DrawColor(0xFF102030),
          strokeWidth: 1.5,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final local =
          transformed.child.primitives.single as RenderTextRunPrimitive;

      expect(local.strokeColorArgb, isNotNull);
      expect(local.strokeWidth, 1.5);
    });

    test('encodes solid text background as a path fill primitive', () {
      const element = ElementState(
        id: 'text',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(
          text: 'Scene',
          fillColor: DrawColor(0x44000000),
          cornerRadius: 6,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;

      expect(
        localPrimitives.whereType<RenderPathFillPrimitive>(),
        hasLength(1),
      );
      expect(localPrimitives.whereType<RenderTextRunPrimitive>(), hasLength(1));
      final background = localPrimitives
          .whereType<RenderPathFillPrimitive>()
          .single;
      expect(background.path.commands, isNotEmpty);
    });

    test('encodes patterned text background fill as hatch primitive', () {
      const element = ElementState(
        id: 'text',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(
          text: 'Scene',
          fillColor: DrawColor(0x44000000),
          fillStyle: FillStyle.line,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
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

  group('SerialNumberSceneEncoder', () {
    const encoder = SerialNumberSceneEncoder();

    test(
      'encodes supported serial number into fill/stroke/text primitives',
      () {
        const element = ElementState(
          id: 'serial',
          rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 120),
          rotation: 0.15,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(
            number: 12,
            color: DrawColor(0xFF112233),
            fillColor: DrawColor(0xFFCCDDEE),
            strokeStyle: StrokeStyle.dashed,
          ),
        );

        final scene = encoder.encodeScene(element: element, scaleFactor: 1);
        final transformed = scene.primitives.single as RenderTransformPrimitive;
        final localPrimitives = transformed.child.primitives;

        expect(
          localPrimitives.whereType<RenderPathFillPrimitive>(),
          hasLength(1),
        );
        expect(
          localPrimitives.whereType<RenderPathStrokePrimitive>(),
          hasLength(1),
        );
        expect(
          localPrimitives.whereType<RenderTextRunPrimitive>(),
          hasLength(1),
        );
        final stroke = localPrimitives
            .whereType<RenderPathStrokePrimitive>()
            .single;
        expect(stroke.dashPattern, isNotNull);
      },
    );

    test('encodes patterned serial-number fill as hatch primitive', () {
      const element = ElementState(
        id: 'serial',
        rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: SerialNumberData(
          fillColor: DrawColor(0xFFCCDDEE),
          fillStyle: FillStyle.line,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;
      final hatch = localPrimitives
          .whereType<RenderHatchPathFillPrimitive>()
          .single;

      expect(hatch.pattern, RenderHatchPattern.line);
      expect(hatch.spacing, greaterThan(0));
      expect(hatch.lineWidth, greaterThan(0));
    });

    test('encodes dotted serial-number stroke as dash pattern', () {
      const element = ElementState(
        id: 'serial',
        rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: SerialNumberData(
          color: DrawColor(0xFF112233),
          strokeStyle: StrokeStyle.dotted,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;
      final stroke = localPrimitives
          .whereType<RenderPathStrokePrimitive>()
          .single;

      expect(stroke.dashPattern, isNotNull);
      expect(stroke.strokeCap, RenderStrokeCap.round);
    });
  });
}
