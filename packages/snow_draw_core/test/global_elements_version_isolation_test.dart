import 'dart:async';

import 'package:test/test.dart';
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

    final events = <DocumentChangedEvent>[];
    final firstEvent = Completer<DocumentChangedEvent>();
    final subscription = store.eventStreamOf<DocumentChangedEvent>().listen((
      event,
    ) {
      events.add(event);
      if (!firstEvent.isCompleted) {
        firstEvent.complete(event);
      }
    });
    addTearDown(subscription.cancel);

    final initialVersion = store.state.domain.document.elementsVersion;

    await store.dispatch(
      const UpdateGlobalElements(
        watermark: WatermarkConfig(text: 'CONFIDENTIAL'),
      ),
    );

    final event = await firstEvent.future;
    await pumpEventQueue();

    expect(
      store.state.domain.document.elementsVersion,
      equals(initialVersion + 1),
    );
    expect(events, hasLength(1));
    expect(event.elementsVersion, equals(initialVersion + 1));
  });
}
