import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/plugin_core.dart';
import 'package:snow_draw_core/draw/input/plugins/create_plugin.dart';
import 'package:snow_draw_core/draw/input/plugins/edit_plugin.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';

void main() {
  group('CreatePlugin update deduplication', () {
    test(
      'skips redundant create updates with identical input payload',
      () async {
        final dispatched = <DrawAction>[];
        final state = _creatingFreeDrawState();
        final context = _pluginContext(
          stateProvider: () => state,
          dispatched: dispatched,
        );
        final plugin = CreatePlugin(
          currentToolTypeId: FreeDrawData.typeIdToken,
        );
        await plugin.onLoad(context);

        const event = PointerMoveInputEvent(
          position: DrawPoint(x: 16, y: 24, pressure: 0.5),
          modifiers: KeyModifiers.none,
          pressure: 0.5,
        );
        await plugin.handleEvent(event);
        await plugin.handleEvent(event);

        final updates = dispatched.whereType<UpdateCreatingElement>().toList();
        expect(updates, hasLength(1));

        await plugin.handleEvent(
          const PointerMoveInputEvent(
            position: DrawPoint(x: 16, y: 24, pressure: 0.5),
            modifiers: KeyModifiers(shift: true),
            pressure: 0.5,
          ),
        );
        expect(dispatched.whereType<UpdateCreatingElement>(), hasLength(2));

        await plugin.onUnload();
      },
    );
  });

  group('EditPlugin update deduplication', () {
    test(
      'skips redundant edit updates with identical pointer payload',
      () async {
        final dispatched = <DrawAction>[];
        final state = _editingState();
        final context = _pluginContext(
          stateProvider: () => state,
          dispatched: dispatched,
        );
        final plugin = EditPlugin();
        await plugin.onLoad(context);

        const event = PointerMoveInputEvent(
          position: DrawPoint(x: 80, y: 48),
          modifiers: KeyModifiers.none,
        );
        await plugin.handleEvent(event);
        await plugin.handleEvent(event);

        expect(dispatched.whereType<UpdateEdit>(), hasLength(1));

        await plugin.handleEvent(
          const PointerMoveInputEvent(
            position: DrawPoint(x: 80, y: 48),
            modifiers: KeyModifiers(alt: true),
          ),
        );
        expect(dispatched.whereType<UpdateEdit>(), hasLength(2));

        await plugin.onUnload();
      },
    );
  });
}

PluginContext _pluginContext({
  required DrawState Function() stateProvider,
  required List<DrawAction> dispatched,
}) {
  final drawContext = DrawContext.withDefaults();
  return PluginContext(
    stateProvider: stateProvider,
    contextProvider: () => drawContext,
    selectionConfigProvider: () => drawContext.configManager.current.selection,
    dispatcher: (action) async {
      dispatched.add(action);
    },
  );
}

DrawState _creatingFreeDrawState() {
  final baseState = DrawState();
  const element = ElementState(
    id: 'creating_free_draw',
    rect: DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: FreeDrawData(),
  );
  final creating = CreatingState(
    element: element,
    startPosition: const DrawPoint(x: 10, y: 10),
    currentRect: element.rect,
    creationMode: const FreeDrawCreationMode(),
  );
  return baseState.copyWith(
    application: baseState.application.copyWith(interaction: creating),
  );
}

DrawState _editingState() {
  final baseState = DrawState();
  const context = MoveEditContext(
    startPosition: DrawPoint.zero,
    startBounds: DrawRect(maxX: 20, maxY: 20),
    selectedIdsAtStart: {'element_1'},
    selectionVersion: 0,
    elementsVersion: 0,
    elementSnapshots: {},
  );
  const editing = EditingState(
    operationId: EditOperationIds.move,
    sessionId: 'session_1',
    context: context,
    currentTransform: MoveTransform.zero,
  );
  return baseState.copyWith(
    application: baseState.application.copyWith(interaction: editing),
  );
}
