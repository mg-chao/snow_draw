import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/snap_toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultDrawStore store;
  late SnapToolbarAdapter adapter;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = DefaultDrawStore(context: context);
    adapter = SnapToolbarAdapter(store: store);
  });

  tearDown(() {
    adapter.dispose();
    store.dispose();
  });

  test('initial state reflects store config', () {
    expect(adapter.isEnabled, store.config.snap.enabled);
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
    expect(store.config.snap.enabled, isFalse);
  });

  test('rapid toggle calls return to original value', () async {
    final before = adapter.isEnabled;
    final first = adapter.toggle();
    final second = adapter.toggle();
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(adapter.isEnabled, before);
    expect(store.config.snap.enabled, before);
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

  test('enabling snap disables grid', () async {
    final gridConfig = store.config.copyWith(
      grid: store.config.grid.copyWith(enabled: true),
    );
    await store.dispatch(UpdateConfig(gridConfig));
    expect(store.config.grid.enabled, isTrue);

    await adapter.setEnabled(enabled: true);
    expect(adapter.isEnabled, isTrue);
    expect(store.config.grid.enabled, isFalse);
  });
}
