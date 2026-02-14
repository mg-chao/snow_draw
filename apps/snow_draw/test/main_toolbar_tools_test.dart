import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/widgets/main_toolbar.dart';

void main() {
  testWidgets('main toolbar exposes all tools and updates the controller', (
    tester,
  ) async {
    final controller = ToolController();
    final strings = AppLocalizations(const Locale('en'));
    final tools = <String, ToolType>{
      strings.toolSelection: ToolType.selection,
      strings.toolRectangle: ToolType.rectangle,
      strings.toolArrow: ToolType.arrow,
      strings.toolLine: ToolType.line,
      strings.toolFreeDraw: ToolType.freeDraw,
      strings.toolHighlight: ToolType.highlight,
      strings.toolText: ToolType.text,
      strings.toolSerialNumber: ToolType.serialNumber,
      strings.toolFilter: ToolType.filter,
    };

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainToolbar(strings: strings, toolController: controller),
        ),
      ),
    );

    for (final tooltip in tools.keys) {
      expect(find.byTooltip(tooltip), findsOneWidget);
    }

    for (final entry in tools.entries) {
      await tester.tap(find.byTooltip(entry.key));
      await tester.pump();
      expect(controller.value, entry.value);
    }
  });

  testWidgets('main toolbar switches to an updated tool controller', (
    tester,
  ) async {
    final initialController = ToolController();
    final replacementController = ToolController();
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(initialController.dispose);
    addTearDown(replacementController.dispose);

    Future<void> pumpWithController(ToolController controller) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MainToolbar(
              key: const ValueKey('main-toolbar'),
              strings: strings,
              toolController: controller,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWithController(initialController);
    await tester.tap(find.byTooltip(strings.toolRectangle));
    await tester.pump();
    expect(initialController.value, ToolType.rectangle);

    await pumpWithController(replacementController);
    await tester.tap(find.byTooltip(strings.toolArrow));
    await tester.pump();

    expect(replacementController.value, ToolType.arrow);
    expect(initialController.value, ToolType.rectangle);
  });
}
