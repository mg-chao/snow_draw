import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry_interface.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/reducers/interaction/create/create_element_reducer.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
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
  test('create element uses filter defaults', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final config = DrawConfig(
      filterStyle: const ElementStyleConfig(
        filterType: CanvasFilterType.gaussianBlur,
        filterStrength: 0.7,
        opacity: 0.4,
      ),
    );

    final deps = _Deps(
      config: config,
      elementRegistry: registry,
      idGenerator: SequentialIdGenerator().call,
    );

    const reducer = CreateElementReducer();
    final next = reducer.reduce(
      DrawState.initial(),
      const CreateElement(
        typeId: FilterData.typeIdToken,
        position: DrawPoint(x: 10, y: 10),
      ),
      deps,
    );

    expect(next, isNotNull);
    final interaction = next!.application.interaction;
    expect(interaction, isA<CreatingState>());

    final creating = interaction as CreatingState;
    final data = creating.element.data as FilterData;
    expect(data.type, CanvasFilterType.gaussianBlur);
    expect(data.strength, 0.7);
    expect(creating.element.opacity, 0.4);
  });
}
