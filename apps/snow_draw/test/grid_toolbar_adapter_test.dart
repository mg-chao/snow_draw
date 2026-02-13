import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/grid_toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultDrawStore store;
  late GridToolbarAdapter adapter;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = DefaultDrawStore(context: context);
    adapter = GridToolbarAdapter(store: store);
  });

  tearDown(() {
    adapter.dispose();
    store.dispose();
  });

  test('initial state reflects store config', () {
    expect(adapter.isEnabled, store.config.grid.enabled);
    expect(adapter.gridSize, store.config.grid.size);
  });

  test('toggle changes enabled state', () async {
    final before = adapter.isEnabled;
    await adapter.toggle();
    expect(adapter.isEnabled, !before);
  });

  test('setEnabled updates notifier', () async {
    await adapter.setEnabled(enabled: true);
    expect(adapter.isEnabled, isTrue);
    await adapter.setEnabled(enabled: false);
    expect(adapter.isEnabled, isFalse);
  });

  test('setGridSize updates notifier', () async {
    await adapter.setGridSize(24);
    expect(adapter.gridSize, 24);
  });

  test('setGridSize clamps to min', () async {
    await adapter.setGridSize(0);
    expect(adapter.gridSize, GridConfig.minSize);
  });

  test('setGridSize clamps to max', () async {
    await adapter.setGridSize(99999);
    expect(adapter.gridSize, GridConfig.maxSize);
  });

  test('setGridSize ignores non-finite values', () async {
    final before = adapter.gridSize;

    await adapter.setGridSize(double.nan);
    await adapter.setGridSize(double.infinity);
    await adapter.setGridSize(double.negativeInfinity);

    expect(adapter.gridSize, before);
    expect(store.config.grid.size, before);
  });

  test('enabledListenable notifies on change', () async {
    final values = <bool>[];
    adapter.enabledListenable.addListener(
      () => values.add(adapter.enabledListenable.value),
    );
    await adapter.setEnabled(enabled: true);
    await adapter.setEnabled(enabled: false);
    expect(values, containsAllInOrder([true, false]));
  });

  test('rapid setEnabled calls honor latest value', () async {
    final first = adapter.setEnabled(enabled: true);
    final second = adapter.setEnabled(enabled: false);
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(adapter.isEnabled, isFalse);
    expect(store.config.grid.enabled, isFalse);
  });

  test('rapid toggle calls return to original value', () async {
    final before = adapter.isEnabled;
    final first = adapter.toggle();
    final second = adapter.toggle();
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(adapter.isEnabled, before);
    expect(store.config.grid.enabled, before);
  });

  test('sizeListenable notifies on change', () async {
    final values = <double>[];
    adapter.sizeListenable.addListener(
      () => values.add(adapter.sizeListenable.value),
    );
    await adapter.setGridSize(32);
    expect(values, contains(32));
  });

  test('dispose is idempotent', () {
    adapter
      ..dispose()
      ..dispose();
  });

  test('toggle after dispose is a no-op', () async {
    adapter.dispose();
    await adapter.toggle();
  });

  test('setEnabled after dispose is a no-op', () async {
    adapter.dispose();
    await adapter.setEnabled(enabled: true);
  });

  test('setGridSize after dispose is a no-op', () async {
    adapter.dispose();
    await adapter.setGridSize(48);
  });

  test('enabling grid disables snap', () async {
    final snapConfig = store.config.copyWith(
      snap: store.config.snap.copyWith(enabled: true),
    );
    await store.dispatch(UpdateConfig(snapConfig));
    expect(store.config.snap.enabled, isTrue);

    await adapter.setEnabled(enabled: true);
    expect(adapter.isEnabled, isTrue);
    expect(store.config.snap.enabled, isFalse);
  });
}
