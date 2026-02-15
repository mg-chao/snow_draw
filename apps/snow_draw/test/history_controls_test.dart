import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/widgets/history_controls.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('history controls track undo/redo availability and dispatch', (
    tester,
  ) async {
    final strings = AppLocalizations(const Locale('en'));
    final store = _createStoreWithSelectedRectangle(elementId: 'rect-1');

    addTearDown(store.dispose);

    await _pumpHistoryControls(tester, strings: strings, store: store);

    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNull);
    expect(_iconButtonForTooltip(tester, strings.redo).onPressed, isNull);

    await _deleteTrackedElement(store, elementId: 'rect-1');
    await tester.pump();

    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNotNull);
    expect(_iconButtonForTooltip(tester, strings.redo).onPressed, isNull);

    await tester.tap(_iconButtonFinderForTooltip(strings.undo));
    await tester.pump();

    expect(store.canUndo, isFalse);
    expect(store.canRedo, isTrue);
    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNull);
    expect(_iconButtonForTooltip(tester, strings.redo).onPressed, isNotNull);

    await tester.tap(_iconButtonFinderForTooltip(strings.redo));
    await tester.pump();

    expect(store.canUndo, isTrue);
    expect(store.canRedo, isFalse);
  });

  testWidgets('history controls unsubscribe from replaced store', (
    tester,
  ) async {
    final strings = AppLocalizations(const Locale('en'));
    final storeA = _createStoreWithSelectedRectangle(elementId: 'rect-a');
    final storeB = _createStoreWithSelectedRectangle(elementId: 'rect-b');

    addTearDown(storeA.dispose);
    addTearDown(storeB.dispose);

    Future<void> pumpWithStore(DefaultDrawStore store) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryControls(
              key: const ValueKey('history-controls'),
              strings: strings,
              store: store,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWithStore(storeA);
    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNull);

    await pumpWithStore(storeB);
    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNull);

    await _deleteTrackedElement(storeA, elementId: 'rect-a');
    await tester.pump();

    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNull);
    expect(storeA.canUndo, isTrue);
    expect(storeB.canUndo, isFalse);

    await _deleteTrackedElement(storeB, elementId: 'rect-b');
    await tester.pump();

    expect(_iconButtonForTooltip(tester, strings.undo).onPressed, isNotNull);

    await tester.tap(_iconButtonFinderForTooltip(strings.undo));
    await tester.pump();

    expect(storeA.canRedo, isFalse);
    expect(storeB.canRedo, isTrue);
  });
}

Future<void> _pumpHistoryControls(
  WidgetTester tester, {
  required AppLocalizations strings,
  required DefaultDrawStore store,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HistoryControls(strings: strings, store: store),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _deleteTrackedElement(
  DefaultDrawStore store, {
  required String elementId,
}) => store.dispatch(DeleteElements(elementIds: [elementId]));

Finder _iconButtonFinderForTooltip(String tooltip) => find.descendant(
  of: find.byTooltip(tooltip),
  matching: find.byType(IconButton),
);

IconButton _iconButtonForTooltip(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(_iconButtonFinderForTooltip(tooltip));

DefaultDrawStore _createStoreWithSelectedRectangle({
  required String elementId,
}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: [
          ElementState(
            id: elementId,
            rect: const DrawRect(maxX: 80, maxY: 60),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: const RectangleData(),
          ),
        ],
      ),
      selection: SelectionState(selectedIds: {elementId}),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
