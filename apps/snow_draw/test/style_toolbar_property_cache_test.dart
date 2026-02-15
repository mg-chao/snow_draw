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
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  testWidgets(
    'toolbar does not re-evaluate properties when context is unchanged',
    (tester) async {
      final counters = _Counters();
      PropertyRegistry.instance
        ..clear()
        ..register(_CountingColorDescriptor(counters));

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

      await _pumpToolbar(tester, adapter, controller);
      expect(counters.extractCalls, 1);
      expect(counters.defaultCalls, 1);

      await _pumpToolbar(tester, adapter, controller);
      expect(counters.extractCalls, 1);
      expect(counters.defaultCalls, 1);
    },
  );

  testWidgets('toolbar re-evaluates properties after style state changes', (
    tester,
  ) async {
    final counters = _Counters();
    PropertyRegistry.instance
      ..clear()
      ..register(_CountingColorDescriptor(counters));

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

    await _pumpToolbar(tester, adapter, controller);
    expect(counters.extractCalls, 1);

    final nextConfig = store.config.copyWith(
      rectangleStyle: store.config.rectangleStyle.copyWith(
        color: const Color(0xFF52C41A),
      ),
    );
    await store.dispatch(UpdateConfig(nextConfig));
    await tester.pump();

    expect(counters.extractCalls, 2);
    expect(counters.defaultCalls, 2);
  });

  testWidgets('registry updates invalidate property evaluation cache', (
    tester,
  ) async {
    final firstCounters = _Counters();
    final secondCounters = _Counters();
    PropertyRegistry.instance
      ..clear()
      ..register(_CountingColorDescriptor(firstCounters));

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

    await _pumpToolbar(tester, adapter, controller);
    expect(firstCounters.extractCalls, 1);
    expect(secondCounters.extractCalls, 0);

    PropertyRegistry.instance.register(
      _CountingColorDescriptor(secondCounters),
    );
    await _pumpToolbar(tester, adapter, controller);

    expect(firstCounters.extractCalls, 1);
    expect(secondCounters.extractCalls, 1);
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester,
  StyleToolbarAdapter adapter,
  ToolController controller,
) => tester.pumpWidget(
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

class _Counters {
  var extractCalls = 0;
  var defaultCalls = 0;
}

class _CountingColorDescriptor extends PropertyDescriptor<Color> {
  _CountingColorDescriptor(this.counters)
    : super(
        id: PropertyIds.color,
        supportedElementTypes: const {ElementType.rectangle},
      );

  final _Counters counters;

  @override
  MixedValue<Color> extractValue(StylePropertyContext context) {
    counters.extractCalls += 1;
    return const MixedValue(value: Colors.black, isMixed: false);
  }

  @override
  Color getDefaultValue(StylePropertyContext context) {
    counters.defaultCalls += 1;
    return Colors.black;
  }
}
