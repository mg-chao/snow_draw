import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultDrawStore store;
  late StyleToolbarAdapter adapter;

  DefaultDrawStore createStoreWithSelection() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);

    const rect = ElementState(
      id: 'r1',
      rect: DrawRect(maxX: 100, maxY: 60),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );

    final initialState = DrawState(
      domain: DomainState(
        document: DocumentState(elements: const [rect]),
        selection: const SelectionState(
          selectedIds: {'r1'},
          selectionVersion: 1,
        ),
      ),
    );

    return DefaultDrawStore(context: context, initialState: initialState);
  }

  group('StyleToolbarAdapter disposal guards', () {
    test('dispose is idempotent', () {
      store = createStoreWithSelection();
      adapter = StyleToolbarAdapter(store: store)
        ..dispose()
        ..dispose();

      store.dispose();
    });

    test('config change after dispose does not throw', () async {
      store = createStoreWithSelection();
      adapter = StyleToolbarAdapter(store: store)..dispose();

      // Dispatch a config change after adapter disposal.
      // This should not throw even though the adapter's
      // stream subscription may still deliver a buffered event.
      await store.dispatch(
        UpdateConfig(
          store.config.copyWith(
            rectangleStyle: store.config.rectangleStyle.copyWith(
              strokeWidth: 99,
            ),
          ),
        ),
      );

      // Pump microtasks so any pending stream events are delivered.
      await pumpEventQueue();

      store.dispose();
    });

    test('state change after dispose does not throw', () async {
      store = createStoreWithSelection();
      adapter = StyleToolbarAdapter(store: store)..dispose();

      // Dispatch a selection change after adapter disposal.
      await store.dispatch(const ClearSelection());
      await pumpEventQueue();

      store.dispose();
    });

    test('stateNotifier value is not updated after dispose', () async {
      store = createStoreWithSelection();
      adapter = StyleToolbarAdapter(store: store);

      final valueBefore = adapter.stateListenable.value;
      adapter.dispose();

      // Trigger a config change that would normally update
      // the adapter's state.
      await store.dispatch(
        UpdateConfig(
          store.config.copyWith(
            rectangleStyle: store.config.rectangleStyle.copyWith(
              strokeWidth: 99,
            ),
          ),
        ),
      );
      await pumpEventQueue();

      // The adapter should not have scheduled a frame callback,
      // but if it did, pump it.
      try {
        SchedulerBinding.instance.handleBeginFrame(Duration.zero);
        SchedulerBinding.instance.handleDrawFrame();
      } on Object {
        // Ignore if no frame was scheduled.
      }

      // Value should remain unchanged since the adapter is
      // disposed.
      expect(adapter.stateListenable.value, valueBefore);

      store.dispose();
    });

    test('applyStyleUpdate after dispose is a no-op', () async {
      store = createStoreWithSelection();
      adapter = StyleToolbarAdapter(store: store);

      final beforeStyle = store.config.rectangleStyle;
      adapter.dispose();
      await adapter.applyStyleUpdate(
        opacity: 0.35,
        toolType: ToolType.rectangle,
      );
      await pumpEventQueue();

      expect(store.config.rectangleStyle, beforeStyle);

      store.dispose();
    });
  });
}
