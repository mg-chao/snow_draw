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
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opacity slider applies updates immediately on change', (
    tester,
  ) async {
    final harness = await _pumpToolbar(
      tester,
      toolType: ToolType.selection,
      initialState: DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [_rectangle]),
          selection: const SelectionState(selectedIds: {'r1'}),
        ),
      ),
    );

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    final opacitySlider = sliders.singleWhere(
      (slider) => (slider.value - 1).abs() < 0.0001,
    );

    opacitySlider.onChanged?.call(0.4);
    await tester.pump();

    expect(
      harness.store.state.domain.document.getElementById('r1')?.opacity,
      closeTo(0.4, 0.0001),
    );
  });

  testWidgets('serial number input applies updates immediately on change', (
    tester,
  ) async {
    final harness = await _pumpToolbar(
      tester,
      toolType: ToolType.selection,
      initialState: DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [_serialNumber]),
          selection: const SelectionState(selectedIds: {'s1'}),
        ),
      ),
    );

    final input = find.byType(TextField);
    expect(input, findsOneWidget);

    await tester.enterText(input, '42');
    await tester.pump();

    final element = harness.store.state.domain.document.getElementById('s1');
    expect(element, isNotNull);
    expect((element!.data as SerialNumberData).number, 42);
  });

  testWidgets('watermark text input applies updates immediately on change', (
    tester,
  ) async {
    final harness = await _pumpToolbar(
      tester,
      toolType: ToolType.watermark,
      initialState: DrawState(),
    );

    final input = find.byType(TextField);
    expect(input, findsOneWidget);

    await tester.enterText(input, 'LIVE');
    await tester.pump();

    expect(
      harness.store.state.domain.document.globalElements.watermark.text,
      'LIVE',
    );
  });
}

const _rectangle = ElementState(
  id: 'r1',
  rect: DrawRect(maxX: 120, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

const _serialNumber = ElementState(
  id: 's1',
  rect: DrawRect(maxX: 120, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: SerialNumberData(),
);

Future<({DefaultDrawStore store})> _pumpToolbar(
  WidgetTester tester, {
  required ToolType toolType,
  required DrawState initialState,
}) async {
  initializePropertyRegistry();

  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  final store = DefaultDrawStore(context: context, initialState: initialState);
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

  return (store: store);
}
