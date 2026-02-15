import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/grid_toolbar_adapter.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/snap_toolbar_adapter.dart';
import 'package:snow_draw/widgets/snap_controls.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DefaultDrawStore createStore() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    return DefaultDrawStore(context: context);
  }

  Color gridIconColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.grid_on)).color!;

  Color snapIconColor(WidgetTester tester) =>
      tester.widget<SnapIcon>(find.byType(SnapIcon)).color;

  testWidgets('snap controls reflect effective mode and ctrl override', (
    tester,
  ) async {
    final store = createStore();
    final snapAdapter = SnapToolbarAdapter(store: store);
    final gridAdapter = GridToolbarAdapter(store: store);
    final ctrlPressed = ValueNotifier<bool>(false);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(() {
      ctrlPressed.dispose();
      snapAdapter.dispose();
      gridAdapter.dispose();
      store.dispose();
    });

    await gridAdapter.setEnabled(enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnapControls(
            strings: strings,
            snapAdapter: snapAdapter,
            gridAdapter: gridAdapter,
            ctrlPressedListenable: ctrlPressed,
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(SnapControls));
    final theme = Theme.of(context);
    final inactiveColor = theme.iconTheme.color ?? Colors.black;

    expect(gridIconColor(tester), theme.colorScheme.primary);
    expect(snapIconColor(tester), inactiveColor);

    ctrlPressed.value = true;
    await tester.pump();

    expect(gridIconColor(tester), inactiveColor);
    expect(snapIconColor(tester), inactiveColor);
  });

  testWidgets(
    'snap controls respond to replaced adapters and ctrl listenable',
    (tester) async {
      final strings = AppLocalizations(const Locale('en'));
      final storeA = createStore();
      final snapAdapterA = SnapToolbarAdapter(store: storeA);
      final gridAdapterA = GridToolbarAdapter(store: storeA);
      final ctrlPressedA = ValueNotifier<bool>(false);
      final storeB = createStore();
      final snapAdapterB = SnapToolbarAdapter(store: storeB);
      final gridAdapterB = GridToolbarAdapter(store: storeB);
      final ctrlPressedB = ValueNotifier<bool>(false);

      addTearDown(() {
        ctrlPressedA.dispose();
        ctrlPressedB.dispose();
        snapAdapterA.dispose();
        gridAdapterA.dispose();
        snapAdapterB.dispose();
        gridAdapterB.dispose();
        storeA.dispose();
        storeB.dispose();
      });

      await snapAdapterA.setEnabled(enabled: true);
      await gridAdapterB.setEnabled(enabled: true);

      Future<void> pumpWith({
        required SnapToolbarAdapter snapAdapter,
        required GridToolbarAdapter gridAdapter,
        required ValueNotifier<bool> ctrlPressed,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SnapControls(
                key: const ValueKey('snap-controls'),
                strings: strings,
                snapAdapter: snapAdapter,
                gridAdapter: gridAdapter,
                ctrlPressedListenable: ctrlPressed,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpWith(
        snapAdapter: snapAdapterA,
        gridAdapter: gridAdapterA,
        ctrlPressed: ctrlPressedA,
      );
      var context = tester.element(find.byKey(const ValueKey('snap-controls')));
      var theme = Theme.of(context);
      var inactiveColor = theme.iconTheme.color ?? Colors.black;
      expect(snapIconColor(tester), theme.colorScheme.primary);
      expect(gridIconColor(tester), inactiveColor);

      await pumpWith(
        snapAdapter: snapAdapterB,
        gridAdapter: gridAdapterB,
        ctrlPressed: ctrlPressedB,
      );
      context = tester.element(find.byKey(const ValueKey('snap-controls')));
      theme = Theme.of(context);
      inactiveColor = theme.iconTheme.color ?? Colors.black;
      expect(snapIconColor(tester), inactiveColor);
      expect(gridIconColor(tester), theme.colorScheme.primary);

      ctrlPressedA.value = true;
      await tester.pump();
      expect(gridIconColor(tester), theme.colorScheme.primary);

      ctrlPressedB.value = true;
      await tester.pump();
      expect(snapIconColor(tester), inactiveColor);
      expect(gridIconColor(tester), inactiveColor);

      ctrlPressedB.value = false;
      await tester.pump();
      final previousGridAValue = gridAdapterA.isEnabled;
      expect(gridAdapterB.isEnabled, isTrue);

      await tester.tap(find.byTooltip('${strings.gridSnapping} (Ctrl)'));
      await tester.pumpAndSettle();

      expect(gridAdapterA.isEnabled, previousGridAValue);
      expect(gridAdapterB.isEnabled, isFalse);
    },
  );
}
