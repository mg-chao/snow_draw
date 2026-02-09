import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/widgets/main_toolbar.dart';

void main() {
  testWidgets('main toolbar shows highlight tool button', (tester) async {
    final controller = ToolController();
    final strings = AppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainToolbar(strings: strings, toolController: controller),
        ),
      ),
    );

    expect(find.byTooltip('Highlight'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlight'));
    await tester.pumpAndSettle();

    expect(controller.value, ToolType.highlight);
  });
}
