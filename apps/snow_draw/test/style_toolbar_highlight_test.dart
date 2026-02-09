import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  testWidgets('style toolbar shows highlight controls', (tester) async {
    initializePropertyRegistry();

    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    await store.dispatch(
      UpdateConfig(
        store.config.copyWith(
          highlightStyle: store.config.highlightStyle.copyWith(
            textStrokeWidth: 2,
          ),
        ),
      ),
    );
    final adapter = StyleToolbarAdapter(store: store);
    final toolController = ToolController(ToolType.highlight);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleToolbar(
            strings: AppLocalizations(const Locale('en')),
            adapter: adapter,
            toolController: toolController,
            size: const Size(800, 600),
            width: 280,
            topInset: 0,
            bottomInset: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Highlight Shape'), findsOneWidget);
    expect(find.text('Highlight Stroke Width'), findsOneWidget);
    expect(find.text('Highlight Stroke Color'), findsOneWidget);
    expect(find.text('Mask Color'), findsOneWidget);
    expect(find.text('Mask Opacity'), findsOneWidget);
  });
}
