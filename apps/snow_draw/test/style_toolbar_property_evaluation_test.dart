import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_descriptor.dart';
import 'package:snow_draw/property_ids.dart';
import 'package:snow_draw/property_registry.dart';
import 'package:snow_draw/style_toolbar_state.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  testWidgets(
    'fill color descriptor is evaluated once for visibility and rendering',
    (tester) async {
      final counters = _Counters();
      PropertyRegistry.instance
        ..clear()
        ..register(_CountingFillColorDescriptor(counters));

      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = DefaultDrawStore(context: context);
      final adapter = StyleToolbarAdapter(store: store);
      final controller = ToolController(ToolType.rectangle);

      addTearDown(controller.dispose);
      addTearDown(adapter.dispose);
      addTearDown(store.dispose);
      addTearDown(PropertyRegistry.instance.clear);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StyleToolbar(
              strings: AppLocalizations(const Locale('en')),
              adapter: adapter,
              toolController: controller,
              size: const Size(800, 600),
              width: 280,
              topInset: 0,
              bottomInset: 0,
            ),
          ),
        ),
      );

      expect(counters.extractCalls, 1);
      expect(counters.defaultCalls, 1);
    },
  );
}

class _Counters {
  var extractCalls = 0;
  var defaultCalls = 0;
}

class _CountingFillColorDescriptor extends PropertyDescriptor<Color> {
  _CountingFillColorDescriptor(this.counters)
    : super(
        id: PropertyIds.fillColor,
        supportedElementTypes: const {ElementType.rectangle},
      );

  final _Counters counters;

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    counters.extractCalls += 1;
    return const MixedValue(value: Colors.transparent, isMixed: false);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) {
    counters.defaultCalls += 1;
    return Colors.transparent;
  }
}
