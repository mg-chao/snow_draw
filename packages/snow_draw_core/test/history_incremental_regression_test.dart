import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('History incremental regression', () {
    test(
      'FinishTextEdit delete keeps serial binding undo/redo behavior stable',
      () async {
        final store = _createStore(
          initialState: _stateWithSerialBoundTextAndActiveTextEdit(),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(elementId: 'text', text: '   ', isNew: false),
        );

        final afterDeleteSerial = _serialData(store, 'serial');
        expect(store.state.domain.document.getElementById('text'), isNull);
        expect(afterDeleteSerial, isNotNull);
        expect(afterDeleteSerial!.textElementId, isNull);

        await store.dispatch(const Undo());

        final afterUndoSerial = _serialData(store, 'serial');
        expect(store.state.domain.document.getElementById('text'), isNotNull);
        expect(afterUndoSerial, isNotNull);
        expect(afterUndoSerial!.textElementId, 'text');

        await store.dispatch(const Redo());

        final afterRedoSerial = _serialData(store, 'serial');
        expect(store.state.domain.document.getElementById('text'), isNull);
        expect(afterRedoSerial, isNotNull);
        expect(afterRedoSerial!.textElementId, isNull);
      },
    );

    test(
      'DuplicateElements keeps serial/text mapping undo/redo behavior stable',
      () async {
        final store = _createStore(initialState: _stateWithSerialBoundText());
        addTearDown(store.dispose);

        await store.dispatch(DuplicateElements(elementIds: ['serial']));

        final afterDuplicate = store.state.domain.document.elements;
        expect(afterDuplicate.length, 4);
        expect(store.canUndo, isTrue);

        final duplicatedSerial = afterDuplicate
            .where((element) => element.id != 'serial')
            .where((element) => element.data is SerialNumberData)
            .single;
        final duplicatedText = afterDuplicate
            .where((element) => element.id != 'text')
            .where((element) => element.data is TextData)
            .single;
        final duplicatedSerialData = duplicatedSerial.data as SerialNumberData;
        expect(duplicatedSerialData.textElementId, duplicatedText.id);

        await store.dispatch(const Undo());

        final afterUndo = store.state.domain.document.elements;
        expect(afterUndo.length, 2);
        expect(
          afterUndo.map((element) => element.id).toSet(),
          equals({'serial', 'text'}),
        );

        await store.dispatch(const Redo());

        final afterRedo = store.state.domain.document.elements;
        final redoDuplicatedSerial = afterRedo
            .where((element) => element.id != 'serial')
            .where((element) => element.data is SerialNumberData)
            .single;
        final redoDuplicatedText = afterRedo
            .where((element) => element.id != 'text')
            .where((element) => element.data is TextData)
            .single;
        final redoDuplicatedSerialData =
            redoDuplicatedSerial.data as SerialNumberData;
        expect(afterRedo.length, 4);
        expect(redoDuplicatedSerialData.textElementId, redoDuplicatedText.id);
      },
    );
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithSerialBoundText() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: const [
        ElementState(
          id: 'serial',
          rect: DrawRect(maxX: 50, maxY: 50),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(textElementId: 'text'),
        ),
        ElementState(
          id: 'text',
          rect: DrawRect(minY: 60, maxX: 50, maxY: 90),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: TextData(text: '1'),
        ),
      ],
    ),
    selection: const SelectionState(selectedIds: {'serial'}),
  ),
);

DrawState _stateWithSerialBoundTextAndActiveTextEdit() {
  final base = _stateWithSerialBoundText();
  return base.copyWith(
    application: base.application.copyWith(
      interaction: const TextEditingState(
        elementId: 'text',
        draftData: TextData(text: '1'),
        rect: DrawRect(minY: 60, maxX: 50, maxY: 90),
        isNew: false,
        opacity: 1,
        rotation: 0,
      ),
    ),
  );
}

SerialNumberData? _serialData(DefaultDrawStore store, String elementId) {
  final element = store.state.domain.document.getElementById(elementId);
  final data = element?.data;
  if (data is! SerialNumberData) {
    return null;
  }
  return data;
}
