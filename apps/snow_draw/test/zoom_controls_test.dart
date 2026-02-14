import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/widgets/zoom_controls.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/view_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('zoom out is disabled at minimum zoom', (tester) async {
    final store = _createStore(zoom: CameraState.minZoom);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(store.dispose);

    await _pumpZoomControls(tester, store: store, strings: strings);

    final zoomOutButton = _iconButtonForTooltip(tester, strings.zoomOut);
    final zoomInButton = _iconButtonForTooltip(tester, strings.zoomIn);

    expect(zoomOutButton.onPressed, isNull);
    expect(zoomInButton.onPressed, isNotNull);
  });

  testWidgets('zoom in is disabled at maximum zoom', (tester) async {
    final store = _createStore(zoom: CameraState.maxZoom);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(store.dispose);

    await _pumpZoomControls(tester, store: store, strings: strings);

    final zoomOutButton = _iconButtonForTooltip(tester, strings.zoomOut);
    final zoomInButton = _iconButtonForTooltip(tester, strings.zoomIn);

    expect(zoomOutButton.onPressed, isNotNull);
    expect(zoomInButton.onPressed, isNull);
  });

  testWidgets('zoom in and zoom out are enabled within zoom bounds', (
    tester,
  ) async {
    final store = _createStore(zoom: 1.5);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(store.dispose);

    await _pumpZoomControls(tester, store: store, strings: strings);

    final zoomOutButton = _iconButtonForTooltip(tester, strings.zoomOut);
    final zoomInButton = _iconButtonForTooltip(tester, strings.zoomIn);

    expect(zoomOutButton.onPressed, isNotNull);
    expect(zoomInButton.onPressed, isNotNull);
  });

  testWidgets('reset zoom is disabled at 100%', (tester) async {
    final store = _createStore(zoom: 1);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(store.dispose);

    await _pumpZoomControls(tester, store: store, strings: strings);

    final resetButton = _textButtonForTooltip(tester, strings.resetZoom);
    expect(resetButton.onPressed, isNull);
  });

  testWidgets('reset zoom is enabled away from 100%', (tester) async {
    final store = _createStore(zoom: 1.2);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(store.dispose);

    await _pumpZoomControls(tester, store: store, strings: strings);

    final resetButton = _textButtonForTooltip(tester, strings.resetZoom);
    expect(resetButton.onPressed, isNotNull);
  });

  testWidgets('zoom controls unsubscribe from a replaced store', (
    tester,
  ) async {
    final strings = AppLocalizations(const Locale('en'));
    final storeA = _createStore(zoom: 1);
    final storeB = _createStore(zoom: 2);

    addTearDown(storeA.dispose);
    addTearDown(storeB.dispose);

    Future<void> pumpWithStore(DefaultDrawStore store) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(
              key: const ValueKey('zoom-controls'),
              strings: strings,
              store: store,
              size: const Size(800, 600),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWithStore(storeA);
    expect(find.text('100%'), findsOneWidget);

    await pumpWithStore(storeB);
    expect(find.text('200%'), findsOneWidget);

    await storeA.dispatch(
      const ZoomCamera(scale: 1.5, center: DrawPoint(x: 400, y: 300)),
    );
    await tester.pump();
    expect(find.text('200%'), findsOneWidget);

    await storeB.dispatch(
      const ZoomCamera(scale: 0.5, center: DrawPoint(x: 400, y: 300)),
    );
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });
}

Future<void> _pumpZoomControls(
  WidgetTester tester, {
  required DefaultDrawStore store,
  required AppLocalizations strings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ZoomControls(
          strings: strings,
          store: store,
          size: const Size(800, 600),
        ),
      ),
    ),
  );
  await tester.pump();
}

IconButton _iconButtonForTooltip(WidgetTester tester, String tooltip) {
  final finder = find.descendant(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder);
}

TextButton _textButtonForTooltip(WidgetTester tester, String tooltip) {
  final finder = find.descendant(
    of: find.byTooltip(tooltip),
    matching: find.byType(TextButton),
  );
  return tester.widget<TextButton>(finder);
}

DefaultDrawStore _createStore({required double zoom}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  final initialState = DrawState(
    application: ApplicationState(
      view: ViewState(camera: CameraState(zoom: zoom)),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
