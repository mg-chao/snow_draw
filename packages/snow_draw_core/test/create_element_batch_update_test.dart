import 'package:test/test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry_interface.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/reducers/interaction/create/create_element_reducer.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/utils/id_generator.dart';

class _Deps implements CreateElementReducerDeps {
  _Deps({
    required this.config,
    required this.elementRegistry,
    required this.idGenerator,
  });

  @override
  final DrawConfig config;

  @override
  final ElementRegistry elementRegistry;

  @override
  final IdGenerator idGenerator;
}

void main() {
  test('UpdateCreatingElementBatch advances free-draw creation '
      'in one reducer pass', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final deps = _Deps(
      config: DrawConfig(),
      elementRegistry: registry,
      idGenerator: SequentialIdGenerator().call,
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
      UpdateCreatingElementBatch(
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
