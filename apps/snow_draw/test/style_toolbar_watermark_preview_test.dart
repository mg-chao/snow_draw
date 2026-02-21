import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('watermark slider drag updates preview and commits on release', (
    tester,
  ) async {
    final harness = await _pumpToolbar(tester);
    final angleSlider = _findWatermarkAngleSlider(tester);

    angleSlider.onChanged?.call(45);
    await tester.pump();

    final preview = harness.adapter.watermarkPreviewListenable.value;
    expect(preview, isNotNull);
    expect(preview!.angle, closeTo(45, 0.0001));
    expect(
      harness.store.state.domain.document.globalElements.watermark.angle,
      ConfigDefaults.defaultWatermarkAngle,
    );

    angleSlider.onChangeEnd?.call(45);
    await tester.pumpAndSettle();

    expect(
      harness.store.state.domain.document.globalElements.watermark.angle,
      closeTo(45, 0.0001),
    );
    expect(harness.adapter.watermarkPreviewListenable.value, isNull);
  });

  testWidgets('watermark preview updates coalesce per frame', (tester) async {
    final harness = await _pumpToolbar(tester);
    var previewNotifications = 0;
    harness.adapter.watermarkPreviewListenable.addListener(() {
      previewNotifications += 1;
    });

    harness.adapter.previewWatermarkUpdate(watermarkAngle: 12);
    harness.adapter.previewWatermarkUpdate(watermarkAngle: 24);
    harness.adapter.previewWatermarkUpdate(watermarkAngle: 36);

    expect(harness.adapter.watermarkPreviewListenable.value, isNull);

    await tester.pump();

    final preview = harness.adapter.watermarkPreviewListenable.value;
    expect(preview, isNotNull);
    expect(preview!.angle, closeTo(36, 0.0001));
    expect(previewNotifications, 1);
  });

  testWidgets(
    'pending coalesced updates keep preview in sync with direct updates',
    (tester) async {
      final harness = await _pumpToolbar(tester);
      final textUpdate = harness.adapter.applyStyleUpdate(
        watermarkText: 'draft',
        toolType: ToolType.watermark,
        historyCoalescing: const HistoryCoalescing(key: 'test.watermark.text'),
      );

      await harness.adapter.applyStyleUpdate(
        watermarkColor: const Color(0xFFFF0000),
        toolType: ToolType.watermark,
      );
      await tester.pumpAndSettle();
      await textUpdate;
      await tester.pumpAndSettle();

      final persisted =
          harness.store.state.domain.document.globalElements.watermark;
      expect(persisted.text, 'draft');
      expect(persisted.color, const DrawColor(0xFFFF0000));
      expect(harness.adapter.watermarkPreviewListenable.value, isNull);
    },
  );
}

Future<({DefaultDrawStore store, StyleToolbarAdapter adapter})> _pumpToolbar(
  WidgetTester tester,
) async {
  initializePropertyRegistry();

  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  final store = DefaultDrawStore(context: context, initialState: DrawState());
  final adapter = StyleToolbarAdapter(store: store);
  final toolController = ToolController(ToolType.watermark);

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

  return (store: store, adapter: adapter);
}

Slider _findWatermarkAngleSlider(WidgetTester tester) {
  final sliders = tester.widgetList<Slider>(find.byType(Slider));
  return sliders.firstWhere((slider) => slider.min == -90 && slider.max == 90);
}
