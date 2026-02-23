import 'package:snow_draw_core/draw/elements/core/typed_element_scene_encoder.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  const encoder = _TestSceneEncoder();

  test('wraps encoded local scene with element transform metadata', () {
    const element = ElementState(
      id: 'typed-scene',
      rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 80),
      rotation: 0.25,
      opacity: 1,
      zIndex: 0,
      data: _TestData(colorArgb: 0xFF123456),
    );

    final scene = encoder.encodeScene(element: element);

    final cullRect = scene.cullRect;
    expect(cullRect, isNotNull);
    expect(cullRect!.center, element.rect.center);
    expect(cullRect.width, greaterThan(element.rect.width));
    expect(cullRect.height, greaterThan(element.rect.height));
    expect(scene.primitives.length, 1);
    final root = scene.primitives.single as RenderTransformPrimitive;
    expect(root.translate, element.center);
    expect(root.rotation, element.rotation);
    expect(root.child.primitives.length, 1);
    final fill = root.child.primitives.single as RenderPathFillPrimitive;
    expect(fill.colorArgb, 0xFF123456);
  });

  test('keeps cull rect unchanged for non-rotated elements', () {
    const element = ElementState(
      id: 'typed-scene-no-rotation',
      rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 80),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: _TestData(colorArgb: 0xFF123456),
    );

    final scene = encoder.encodeScene(element: element);

    expect(scene.cullRect, element.rect);
  });

  test('throws state error for mismatched element data types', () {
    const element = ElementState(
      id: 'wrong-data',
      rect: DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: _OtherData(),
    );

    expect(() => encoder.encodeScene(element: element), throwsStateError);
  });
}

final class _TestSceneEncoder extends TypedElementSceneEncoder<_TestData> {
  const _TestSceneEncoder();

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required _TestData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    final localScene = SceneBuilder()
      ..addPathFill(
        path: const RenderPath(<RenderPathCommand>[
          RenderMoveTo(DrawPoint.zero),
          RenderLineTo(DrawPoint(x: 1, y: 0)),
          RenderLineTo(DrawPoint(x: 1, y: 1)),
          RenderClosePath(),
        ]),
        colorArgb: data.colorArgb,
      );
    return composeElementScene(
      element: element,
      localScene: localScene.build(),
    );
  }
}

class _TestData extends ElementData {
  const _TestData({required this.colorArgb});

  static const typeIdToken = ElementTypeId<_TestData>('typed_scene_test_data');

  final int colorArgb;

  @override
  ElementTypeId<_TestData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'typeId': typeId.value,
    'colorArgb': colorArgb,
  };
}

class _OtherData extends ElementData {
  const _OtherData();

  static const typeIdToken = ElementTypeId<_OtherData>(
    'typed_scene_other_data',
  );

  @override
  ElementTypeId<_OtherData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'typeId': typeId.value};
}
