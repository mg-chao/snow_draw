import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/serial_number_operations_toolbar.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/models/view_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toolbar remains visible near horizontal viewport edges', (
    tester,
  ) async {
    _setSurfaceSize(tester, const Size(320, 240));

    final store = _createStore(
      elementId: 'serial-edge-horizontal',
      rect: const DrawRect(minX: 280, minY: 40, maxX: 320, maxY: 80),
      cameraPosition: DrawPoint.zero,
    );
    final adapter = StyleToolbarAdapter(store: store);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await _pumpToolbar(
      tester,
      strings: strings,
      store: store,
      adapter: adapter,
    );

    final toolbarRect = _toolbarRect(tester);
    expect(toolbarRect.left, greaterThanOrEqualTo(0));
    expect(toolbarRect.right, lessThanOrEqualTo(320));
  });

  testWidgets(
    'toolbar renders above the selection when there is no space below',
    (tester) async {
      _setSurfaceSize(tester, const Size(320, 240));

      final store = _createStore(
        elementId: 'serial-edge-vertical',
        rect: const DrawRect(minX: 60, minY: 200, maxX: 120, maxY: 220),
        cameraPosition: DrawPoint.zero,
      );
      final adapter = StyleToolbarAdapter(store: store);
      final strings = AppLocalizations(const Locale('en'));

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await _pumpToolbar(
        tester,
        strings: strings,
        store: store,
        adapter: adapter,
      );

      final toolbarRect = _toolbarRect(tester);
      expect(toolbarRect.bottom, lessThanOrEqualTo(240));
      expect(toolbarRect.top, lessThan(200));
    },
  );

  testWidgets(
    'toolbar stays within viewport when selection is below the visible area',
    (tester) async {
      _setSurfaceSize(tester, const Size(320, 240));

      final store = _createStore(
        elementId: 'serial-offscreen-bottom',
        rect: const DrawRect(minX: 80, minY: 300, maxX: 140, maxY: 340),
        cameraPosition: DrawPoint.zero,
      );
      final adapter = StyleToolbarAdapter(store: store);
      final strings = AppLocalizations(const Locale('en'));

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      await _pumpToolbar(
        tester,
        strings: strings,
        store: store,
        adapter: adapter,
      );

      final toolbarRect = _toolbarRect(tester);
      expect(toolbarRect.top, greaterThanOrEqualTo(0));
      expect(toolbarRect.bottom, lessThanOrEqualTo(240));
    },
  );

  testWidgets('toolbar follows camera updates from the current store', (
    tester,
  ) async {
    final store = _createStore(
      elementId: 'serial-1',
      rect: const DrawRect(minX: 20, minY: 10, maxX: 80, maxY: 60),
      cameraPosition: const DrawPoint(x: 8, y: 12),
    );
    final adapter = StyleToolbarAdapter(store: store);
    final strings = AppLocalizations(const Locale('en'));

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await _pumpToolbar(
      tester,
      strings: strings,
      store: store,
      adapter: adapter,
    );

    final initial = _toolbarPosition(tester);

    await store.dispatch(const MoveCamera(dx: 25, dy: 15));
    await tester.pump();

    final moved = _toolbarPosition(tester);
    expect(moved.left, closeTo(initial.left! + 25, 0.001));
    expect(moved.top, closeTo(initial.top! + 15, 0.001));
  });

  testWidgets('toolbar keeps listening after replacing the store', (
    tester,
  ) async {
    final strings = AppLocalizations(const Locale('en'));
    final storeA = _createStore(
      elementId: 'serial-a',
      rect: const DrawRect(maxX: 40, maxY: 40),
      cameraPosition: DrawPoint.zero,
    );
    final adapterA = StyleToolbarAdapter(store: storeA);
    final storeB = _createStore(
      elementId: 'serial-b',
      rect: const DrawRect(minX: 120, minY: 80, maxX: 220, maxY: 180),
      cameraPosition: const DrawPoint(x: 50, y: 30),
    );
    final adapterB = StyleToolbarAdapter(store: storeB);

    addTearDown(adapterA.dispose);
    addTearDown(storeA.dispose);
    addTearDown(adapterB.dispose);
    addTearDown(storeB.dispose);

    await _pumpToolbar(
      tester,
      strings: strings,
      store: storeA,
      adapter: adapterA,
    );
    await _pumpToolbar(
      tester,
      strings: strings,
      store: storeB,
      adapter: adapterB,
    );

    final beforeMove = _toolbarPosition(tester);

    await storeB.dispatch(const MoveCamera(dx: 18, dy: 22));
    await tester.pump();

    final afterMove = _toolbarPosition(tester);
    expect(afterMove.left, closeTo(beforeMove.left! + 18, 0.001));
    expect(afterMove.top, closeTo(beforeMove.top! + 22, 0.001));
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required AppLocalizations strings,
  required DefaultDrawStore store,
  required StyleToolbarAdapter adapter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            SerialNumberOperationsToolbar(
              key: const ValueKey('serial-toolbar'),
              strings: strings,
              store: store,
              adapter: adapter,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byKey(const ValueKey('serial-toolbar')), findsOneWidget);
  expect(find.byType(Positioned), findsOneWidget);
}

Positioned _toolbarPosition(WidgetTester tester) =>
    tester.widget<Positioned>(find.byType(Positioned));

Rect _toolbarRect(WidgetTester tester) {
  final materialFinder = find.descendant(
    of: find.byKey(const ValueKey('serial-toolbar')),
    matching: find.byWidgetPredicate(
      (widget) => widget is Material && widget.elevation == 3,
    ),
  );
  expect(materialFinder, findsOneWidget);
  final topLeft = tester.getTopLeft(materialFinder);
  final bottomRight = tester.getBottomRight(materialFinder);
  return Rect.fromPoints(topLeft, bottomRight);
}

void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DefaultDrawStore _createStore({
  required String elementId,
  required DrawRect rect,
  required DrawPoint cameraPosition,
}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  final element = ElementState(
    id: elementId,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: const SerialNumberData(number: 3),
  );

  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(elements: [element]),
      selection: SelectionState(selectedIds: {elementId}),
    ),
    application: ApplicationState(
      view: ViewState(camera: CameraState(position: cameraPosition)),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
