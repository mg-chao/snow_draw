import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('Serial number generation', () {
    test(
      'new serial uses max existing number + 1 when defaults are stale',
      () async {
        final store = _createStore(
          initialState: _stateWithExistingSerial(number: 3),
          config: DrawConfig(
            serialNumberStyle: const ElementStyleConfig(serialNumber: 3),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const CreateElement(
            typeId: SerialNumberData.typeIdToken,
            position: DrawPoint(x: 180, y: 120),
          ),
        );
        await store.dispatch(const FinishCreateElement());

        final created = _latestSerialData(store.state);
        expect(created.number, 4);
        expect(store.config.serialNumberStyle.serialNumber, 5);
      },
    );

    test('new serial honors higher configured start number', () async {
      final store = _createStore(
        initialState: _stateWithExistingSerial(number: 3),
        config: DrawConfig(
          serialNumberStyle: const ElementStyleConfig(serialNumber: 10),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        const CreateElement(
          typeId: SerialNumberData.typeIdToken,
          position: DrawPoint(x: 220, y: 140),
        ),
      );
      await store.dispatch(const FinishCreateElement());

      final created = _latestSerialData(store.state);
      expect(created.number, 10);
      expect(store.config.serialNumberStyle.serialNumber, 11);
    });
  });
}

DefaultDrawStore _createStore({
  required DrawState initialState,
  required DrawConfig config,
}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(
    elementRegistry: registry,
    configManager: ConfigManager(config),
  );
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithExistingSerial({required int number}) => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: [
        ElementState(
          id: 'serial-existing',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(number: number),
        ),
      ],
    ),
  ),
);

SerialNumberData _latestSerialData(DrawState state) {
  final serialElements = state.domain.document.elements.where(
    (element) => element.data is SerialNumberData,
  );
  final createdElement = serialElements.last;
  return createdElement.data as SerialNumberData;
}
