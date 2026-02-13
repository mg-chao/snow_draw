import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

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
}
