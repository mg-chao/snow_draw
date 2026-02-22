import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_scene_encoder.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_scene_encoder.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/render/scene/render_scene.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('HighlightSceneEncoder', () {
    const encoder = HighlightSceneEncoder();

    test('encodes fill as multiply group and stroke as regular primitive', () {
      const element = ElementState(
        id: 'highlight',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0.2,
        opacity: 1,
        zIndex: 0,
        data: HighlightData(
          shape: HighlightShape.ellipse,
          color: DrawColor(0x88FFFF00),
          strokeColor: DrawColor(0xFF112233),
          strokeWidth: 2,
        ),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      final transformed = scene.primitives.single as RenderTransformPrimitive;
      final localPrimitives = transformed.child.primitives;

      expect(localPrimitives, hasLength(2));
      expect(localPrimitives.first, isA<RenderFilterGroupPrimitive>());
      expect(localPrimitives.last, isA<RenderPathStrokePrimitive>());

      final fillGroup = localPrimitives.first as RenderFilterGroupPrimitive;
      expect(fillGroup.filter, isA<RenderBlendMultiplyFilter>());
      expect(fillGroup.child.primitives, hasLength(1));
      expect(fillGroup.child.primitives.single, isA<RenderPathFillPrimitive>());
    });
  });

  group('FilterSceneEncoder', () {
    const encoder = FilterSceneEncoder();

    test('emits no-op scene for compositor-owned filters', () {
      const element = ElementState(
        id: 'filter',
        rect: DrawRect(minX: 10, minY: 20, maxX: 210, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      );

      final scene = encoder.encodeScene(element: element, scaleFactor: 1);
      expect(scene.primitives, isEmpty);
    });
  });
}
