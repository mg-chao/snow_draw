import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/reducers/interaction/create/create_element_reducer.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/utils/id_generator.dart';

void main() {
  test('create element uses highlight defaults', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final deps = DrawContext.withDefaults(
      config: DrawConfig(
        highlightStyle: const ElementStyleConfig(
          color: Color(0xFF00FF00),
          textStrokeColor: Color(0xFF0000FF),
          textStrokeWidth: 3,
          highlightShape: HighlightShape.ellipse,
          opacity: 0.4,
        ),
      ),
      elementRegistry: registry,
      idGenerator: SequentialIdGenerator().call,
    );

    final next = const CreateElementReducer().reduce(
      DrawState.initial(),
      const CreateElement(
        typeId: HighlightData.typeIdToken,
        position: DrawPoint(x: 10, y: 10),
      ),
      deps,
    )!;
    final creating = next.application.interaction as CreatingState;
    final data = creating.element.data as HighlightData;
    expect(data.color, const Color(0xFF00FF00));
    expect(data.strokeColor, const Color(0xFF0000FF));
    expect(data.strokeWidth, 3);
    expect(data.shape, HighlightShape.ellipse);
    expect(creating.element.opacity, 0.4);
  });
}
