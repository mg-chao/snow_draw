import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/events/error_events.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mask-only update does not emit UpdateElementsStyle validation errors',
    () async {
      final store = _createStore(selectedIds: const {'h1'});
      final adapter = StyleToolbarAdapter(store: store);
      final validationEvents = <ValidationFailedEvent>[];
      final subscription = store.eventStream
          .where((event) => event is ValidationFailedEvent)
          .cast<ValidationFailedEvent>()
          .listen(validationEvents.add);

      addTearDown(subscription.cancel);
      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        maskOpacity: 0.6,
        toolType: ToolType.highlight,
      );
      await pumpEventQueue();

      expect(
        validationEvents.where(
          (event) => event.action == 'UpdateElementsStyle',
        ),
        isEmpty,
      );
      expect(store.config.highlight.maskOpacity, closeTo(0.6, 0.0001));
    },
  );

  test(
    'highlights-only scope does not mutate selected text stroke width',
    () async {
      final store = _createStore(selectedIds: const {'h1', 't1'});
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await adapter.applyStyleUpdate(
        textStrokeWidth: 0,
        toolType: ToolType.highlight,
        scope: StyleUpdateScope.highlightsOnly,
      );
      await pumpEventQueue();

      final highlight =
          store.state.domain.document.getElementById('h1')?.data
              as HighlightData;
      final text =
          store.state.domain.document.getElementById('t1')?.data as TextData;

      expect(highlight.strokeWidth, 0);
      expect(text.strokeWidth, 3);
    },
  );
}

DefaultDrawStore _createStore({required Set<String> selectedIds}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  const highlight = ElementState(
    id: 'h1',
    rect: DrawRect(maxX: 100, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: HighlightData(strokeWidth: 2),
  );
  const text = ElementState(
    id: 't1',
    rect: DrawRect(minX: 120, maxX: 220, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: TextData(strokeWidth: 3),
  );

  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [highlight, text]),
      selection: SelectionState(selectedIds: selectedIds),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
