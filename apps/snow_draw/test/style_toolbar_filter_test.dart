import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  testWidgets('style toolbar shows filter controls', (tester) async {
    initializePropertyRegistry();

    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    final adapter = StyleToolbarAdapter(store: store);
    final toolController = ToolController(ToolType.filter);

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

    expect(find.text('Filter Type'), findsOneWidget);
    expect(find.text('Filter Strength'), findsOneWidget);
    expect(find.byType(DropdownButton<Object>), findsOneWidget);

    await adapter.applyStyleUpdate(
      filterType: CanvasFilterType.grayscale,
      toolType: ToolType.filter,
    );
    await tester.pumpAndSettle();

    expect(find.text('Filter Type'), findsOneWidget);
    expect(find.text('Filter Strength'), findsNothing);
  });
}
