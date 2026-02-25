import 'package:snow_draw_engine/draw/actions/draw_actions.dart';
import 'package:snow_draw_engine/draw/config/config_manager.dart';
import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/reducers/interaction/create/create_element_reducer.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/utils/id_generator.dart';
import 'package:test/test.dart';

IdGenerator _testIdGenerator({String prefix = 'id', int startFrom = 1}) {
  var counter = startFrom;
  return () => '$prefix-${counter++}';
}

void main() {
  test('UpdateCreatingElement advances free-draw creation '
      'in one reducer pass', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final deps = DrawContext.withDefaults(
      elementRegistry: registry,
      idGenerator: _testIdGenerator(),
      configManager: ConfigManager(DrawConfig()),
    );
    const reducer = CreateElementReducer();

    final started = reducer.reduce(
      DrawState.initial(),
      const CreateElement(
        typeId: FreeDrawData.typeIdToken,
        position: DrawPoint(x: 10, y: 10),
      ),
      deps,
    )!;

    final updated = reducer.reduce(
      started,
      UpdateCreatingElement(
        positions: const [
          DrawPoint(x: 16, y: 20, pressure: 0.2),
          DrawPoint(x: 28, y: 34, pressure: 0.3),
          DrawPoint(x: 40, y: 50, pressure: 0.4),
        ],
      ),
      deps,
    )!;

    final creating = updated.application.interaction as CreatingState;
    final freeDrawMode = creating.creationMode as FreeDrawCreationMode;
    expect(freeDrawMode.revision, 1);
    expect(freeDrawMode.worldPoints?.length, greaterThan(2));
    expect(creating.currentRect.maxX, greaterThan(10));
    expect(creating.currentRect.maxY, greaterThan(10));
  });
}
