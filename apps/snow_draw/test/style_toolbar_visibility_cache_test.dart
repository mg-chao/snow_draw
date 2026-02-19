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

void main() {
  testWidgets('keeps rendered toolbar subtree offstage when hidden', (
    tester,
  ) async {
    initializePropertyRegistry();

    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    final adapter = StyleToolbarAdapter(store: store);
    final controller = ToolController(ToolType.rectangle);

    addTearDown(controller.dispose);
    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      _ToolbarHost(adapter: adapter, toolController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Color'), findsOneWidget);

    controller.setTool(ToolType.selection);
    await tester.pumpAndSettle();

    expect(find.text('Color'), findsNothing);
    expect(find.text('Color', skipOffstage: false), findsOneWidget);
  });
}

class _ToolbarHost extends StatelessWidget {
  const _ToolbarHost({
    required StyleToolbarAdapter adapter,
    required ToolController toolController,
  }) : _adapter = adapter,
       _toolController = toolController;

  final StyleToolbarAdapter _adapter;
  final ToolController _toolController;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: StyleToolbar(
        strings: AppLocalizations(const Locale('en')),
        adapter: _adapter,
        toolController: _toolController,
        size: const Size(800, 600),
        width: 280,
        topInset: 0,
        bottomInset: 0,
      ),
    ),
  );
}
