import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
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
    'concurrent default style updates keep all requested rectangle fields',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      final first = adapter.applyStyleUpdate(
        color: const Color(0xFF00FF00),
        toolType: ToolType.rectangle,
      );
      final second = adapter.applyStyleUpdate(
        strokeWidth: 9,
        toolType: ToolType.rectangle,
      );
      await Future.wait([first, second]);
      await pumpEventQueue();

      expect(store.config.rectangleStyle.color, const Color(0xFF00FF00));
      expect(store.config.rectangleStyle.strokeWidth, 9);
    },
  );

  test('font family updates normalize surrounding whitespace '
      'for text and defaults', () async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);

    const textElement = ElementState(
      id: 'text-1',
      rect: DrawRect(maxX: 140, maxY: 60),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(),
    );
    final initialState = DrawState(
      domain: DomainState(
        document: DocumentState(elements: const [textElement]),
        selection: const SelectionState(selectedIds: {'text-1'}),
      ),
    );

    final store = DefaultDrawStore(
      context: context,
      initialState: initialState,
    );
    final adapter = StyleToolbarAdapter(store: store);
    const requestedFamily = '  __integration_font__  ';

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await adapter.applyStyleUpdate(
      fontFamily: requestedFamily,
      toolType: ToolType.text,
    );
    await pumpEventQueue();

    final updated = store.state.domain.document.getElementById('text-1')?.data;
    expect(updated, isA<TextData>());
    expect((updated! as TextData).fontFamily, '__integration_font__');
    expect(store.config.textStyle.fontFamily, '__integration_font__');
  });

  test(
    'default style updates preserve newer external config before stream sync',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      final externalConfig = store.config.copyWith(
        lineStyle: store.config.lineStyle.copyWith(strokeWidth: 17),
      );
      await store.dispatch(UpdateConfig(externalConfig));

      await adapter.applyStyleUpdate(
        color: const Color(0xFFAA22CC),
        toolType: ToolType.rectangle,
      );
      await pumpEventQueue();

      expect(store.config.rectangleStyle.color, const Color(0xFFAA22CC));
      expect(store.config.lineStyle.strokeWidth, 17);
    },
  );
}
