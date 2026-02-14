import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/toolbar_adapter.dart';
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

  testWidgets('z-order changes do not publish style toolbar updates', (
    tester,
  ) async {
    final store = _createStore(selectedIds: const {'r1'});
    final adapter = StyleToolbarAdapter(store: store);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    var notifications = 0;
    adapter.stateListenable.addListener(() {
      notifications += 1;
    });

    final before = store.state.domain.document.getElementById('r1');
    expect(before, isNotNull);

    await adapter.changeZOrder(ZIndexOperation.bringToFront);
    await tester.pump();

    final after = store.state.domain.document.getElementById('r1');
    expect(after, isNotNull);
    expect(after!.zIndex, greaterThan(before!.zIndex));
    expect(notifications, 0);
  });

  testWidgets('opacity changes publish style toolbar updates', (tester) async {
    final store = _createStore(selectedIds: const {'r1'});
    final adapter = StyleToolbarAdapter(store: store);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    var notifications = 0;
    adapter.stateListenable.addListener(() {
      notifications += 1;
    });

    await store.dispatch(
      UpdateElementsStyle(elementIds: const ['r1'], opacity: 0.42),
    );
    await tester.pump();

    final styleValues = adapter.stateListenable.value.styleValues;
    expect(styleValues.opacity.isMixed, isFalse);
    expect(styleValues.opacity.value, closeTo(0.42, 0.0001));
    expect(notifications, 1);
  });
}

DefaultDrawStore _createStore({required Set<String> selectedIds}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);

  const first = ElementState(
    id: 'r1',
    rect: DrawRect(maxX: 80, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  const second = ElementState(
    id: 'r2',
    rect: DrawRect(minX: 120, maxX: 220, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  );

  final initialState = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [first, second]),
      selection: SelectionState(selectedIds: selectedIds),
    ),
  );

  return DefaultDrawStore(context: context, initialState: initialState);
}
