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
    'toolbar ignores descriptors whose value type does not match the id',
    (tester) async {
      final invalidFillColorDescriptor = _InvalidFillColorDescriptor();
      PropertyRegistry.instance
        ..clear()
        ..register(_ConstantColorDescriptor())
        ..register(invalidFillColorDescriptor);

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
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Fill Color'), findsNothing);
      expect(invalidFillColorDescriptor.extractCalls, 1);
      expect(invalidFillColorDescriptor.defaultValueCalls, 1);
    },
  );
}

class _ConstantColorDescriptor extends PropertyDescriptor<Color> {
  _ConstantColorDescriptor()
    : super(
        id: PropertyIds.color,
        supportedElementTypes: const {ElementType.rectangle},
      );

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) =>
      const MixedValue<Color>(value: Colors.black, isMixed: false);

  @override
  Color getDefaultValue(StylePropertyContext context) => Colors.black;
}

class _InvalidFillColorDescriptor extends PropertyDescriptor<int> {
  _InvalidFillColorDescriptor()
    : super(
        id: PropertyIds.fillColor,
        supportedElementTypes: const {ElementType.rectangle},
      );

  var extractCalls = 0;
  var defaultValueCalls = 0;

  @override
  MixedValue<int> extractValue(StylePropertyContext context) {
    extractCalls += 1;
    return const MixedValue<int>(value: 7, isMixed: false);
  }

  @override
  int getDefaultValue(StylePropertyContext context) {
    defaultValueCalls += 1;
    return 7;
  }
}
