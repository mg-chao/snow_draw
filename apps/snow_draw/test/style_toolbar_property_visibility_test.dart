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
  testWidgets(
    'text toolbar hides dependent properties when defaults disable them',
    (tester) async {
      await _pumpToolbar(tester, toolType: ToolType.text);

      expect(find.text('Fill Color'), findsOneWidget);
      expect(find.text('Fill Style'), findsNothing);
      expect(find.text('Corner Radius'), findsNothing);
      expect(find.text('Text Stroke Width'), findsOneWidget);
      expect(find.text('Text Stroke Color'), findsNothing);
    },
  );

  testWidgets(
    'text toolbar shows dependent properties when defaults enable them',
    (tester) async {
      await _pumpToolbar(
        tester,
        toolType: ToolType.text,
        configure: (store) async {
          final nextTextStyle = store.config.textStyle.copyWith(
            fillColor: const Color(0xFFFFCCC7),
            textStrokeWidth: 2,
          );
          await store.dispatch(
            UpdateConfig(store.config.copyWith(textStyle: nextTextStyle)),
          );
        },
      );

      expect(find.text('Fill Style'), findsOneWidget);
      expect(find.text('Corner Radius'), findsOneWidget);
      expect(find.text('Text Stroke Color'), findsOneWidget);
    },
  );

  testWidgets(
    'highlight toolbar hides stroke color when highlight stroke width is zero',
    (tester) async {
      await _pumpToolbar(
        tester,
        toolType: ToolType.highlight,
        configure: (store) async {
          final nextHighlightStyle = store.config.highlightStyle.copyWith(
            textStrokeWidth: 0,
          );
          await store.dispatch(
            UpdateConfig(
              store.config.copyWith(highlightStyle: nextHighlightStyle),
            ),
          );
        },
      );

      expect(find.text('Highlight Stroke Width'), findsOneWidget);
      expect(find.text('Highlight Stroke Color'), findsNothing);
    },
  );
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required ToolType toolType,
  Future<void> Function(DefaultDrawStore store)? configure,
}) async {
  initializePropertyRegistry();

  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  final store = DefaultDrawStore(context: context);
  if (configure != null) {
    await configure(store);
  }
  final adapter = StyleToolbarAdapter(store: store);
  final toolController = ToolController(toolType);

  addTearDown(toolController.dispose);
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
}
