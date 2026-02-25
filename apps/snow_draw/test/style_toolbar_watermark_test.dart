import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

void main() {
  testWidgets('style toolbar shows watermark controls', (tester) async {
    initializePropertyRegistry();

    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    final adapter = StyleToolbarAdapter(store: store);
    final toolController = ToolController(ToolType.watermark);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);
    addTearDown(toolController.dispose);

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

    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Watermark Text'), findsOneWidget);
    expect(find.text('Font Size'), findsOneWidget);
    expect(find.text('Font Family'), findsOneWidget);
    expect(find.text('Watermark Angle'), findsOneWidget);
    expect(find.text('Watermark Gap'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
  });
}
