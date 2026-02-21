import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  test('global element updates bump elementsVersion and emit '
      'document change events', () async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    addTearDown(store.dispose);

    final initialVersion = store.state.domain.document.elementsVersion;
    final eventFuture = store.eventStreamOf<DocumentChangedEvent>().first;

    await store.dispatch(
      const UpdateGlobalElements(
        watermark: WatermarkConfig(text: 'CONFIDENTIAL'),
      ),
    );

    final event = await eventFuture;

    expect(
      store.state.domain.document.elementsVersion,
      equals(initialVersion + 1),
    );
    expect(event.elementsVersion, equals(initialVersion + 1));
  });
}
