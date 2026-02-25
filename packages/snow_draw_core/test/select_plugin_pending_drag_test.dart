import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/plugin_core.dart';
import 'package:snow_draw_core/draw/input/plugins/select_plugin.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('SelectPlugin pending drag handling', () {
    test('starts move edit for pending move with selection', () async {
      final dispatched = <DrawAction>[];
      final state = _pendingDragState(
        intent: const PendingMoveIntent(),
        selectedIds: {'selected_1'},
      );
      final plugin = SelectPlugin();
      await plugin.onLoad(
        _pluginContext(stateProvider: () => state, dispatched: dispatched),
      );

      final result = await plugin.handleEvent(
        PointerMoveInputEvent(
          position: const DrawPoint(x: 40, y: 20),
          modifiers: KeyModifiers.none,
        ),
      );

      expect(result.isHandled, isTrue);
      expect(dispatched.first, isA<ClearDragPending>());
      expect(dispatched.whereType<StartEdit>(), hasLength(1));

      await plugin.onUnload();
    });

    test(
      'does not start move edit for pending move without selection',
      () async {
        final dispatched = <DrawAction>[];
        final state = _pendingDragState(intent: const PendingMoveIntent());
        final plugin = SelectPlugin();
        await plugin.onLoad(
          _pluginContext(stateProvider: () => state, dispatched: dispatched),
        );

        final result = await plugin.handleEvent(
          PointerMoveInputEvent(
            position: const DrawPoint(x: 40, y: 20),
            modifiers: KeyModifiers.none,
          ),
        );

        expect(result.isHandled, isTrue);
        expect(dispatched.whereType<ClearDragPending>(), hasLength(1));
        expect(dispatched.whereType<StartEdit>(), isEmpty);

        await plugin.onUnload();
      },
    );

    test('starts move edit for pending select when selection exists', () async {
      final dispatched = <DrawAction>[];
      final state = _pendingDragState(
        intent: const PendingSelectIntent(
          elementId: 'target',
          addToSelection: false,
        ),
        selectedIds: {'selected_1', 'selected_2'},
      );
      final plugin = SelectPlugin();
      await plugin.onLoad(
        _pluginContext(stateProvider: () => state, dispatched: dispatched),
      );

      final result = await plugin.handleEvent(
        PointerMoveInputEvent(
          position: const DrawPoint(x: 40, y: 20),
          modifiers: KeyModifiers.none,
        ),
      );

      expect(result.isHandled, isTrue);
      expect(dispatched.whereType<ClearDragPending>(), hasLength(1));
      expect(dispatched.whereType<StartEdit>(), hasLength(1));

      await plugin.onUnload();
    });
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

DrawState _pendingDragState({
  required PendingIntent intent,
  Set<String> selectedIds = const {},
}) {
  final base = DrawState();
  return base.copyWith(
    domain: base.domain.withSelection(selectedIds),
    application: base.application.copyWith(
      interaction: DragPendingState(
        pointerDownPosition: const DrawPoint(x: 10, y: 10),
        intent: intent,
      ),
    ),
  );
}
