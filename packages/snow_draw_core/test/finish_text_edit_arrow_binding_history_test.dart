import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('FinishTextEdit arrow binding history', () {
    test(
      'deleting text via FinishTextEdit clears arrow bindings to that text',
      () async {
        final store = _createStore(initialState: _stateWithActiveTextDelete());
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(elementId: _textId, text: '   ', isNew: false),
        );

        expect(store.state.domain.document.getElementById(_textId), isNull);
        expect(_arrowData(store).startBinding, isNull);
        expect(_arrowData(store).startIsSpecial, isNull);
      },
    );

    test('undo and redo keep arrow binding cleanup reversible', () async {
      final store = _createStore(initialState: _stateWithActiveTextDelete());
      addTearDown(store.dispose);

      final originalData = _arrowData(store);

      await store.dispatch(
        const FinishTextEdit(elementId: _textId, text: '   ', isNew: false),
      );

      expect(store.canUndo, isTrue);
      expect(_arrowData(store).startBinding, isNull);
      expect(_arrowData(store).startIsSpecial, isNull);

      await store.dispatch(const Undo());

      expect(store.state.domain.document.getElementById(_textId), isNotNull);
      expect(_arrowData(store).startBinding, equals(originalData.startBinding));
      expect(
        _arrowData(store).startIsSpecial,
        equals(originalData.startIsSpecial),
      );

      await store.dispatch(const Redo());

      expect(store.state.domain.document.getElementById(_textId), isNull);
      expect(_arrowData(store).startBinding, isNull);
      expect(_arrowData(store).startIsSpecial, isNull);
    });
  });
}

const _textId = 'text-1';

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithActiveTextDelete() {
  const textRect = DrawRect(minX: 10, minY: 10, maxX: 150, maxY: 70);
  const textElement = ElementState(
    id: _textId,
    rect: textRect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: TextData(text: 'before'),
  );

  const arrowRect = DrawRect(minX: 40, minY: 40, maxX: 240, maxY: 41);
  const arrowElement = ElementState(
    id: 'arrow-1',
    rect: arrowRect,
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: ArrowData(
      points: [DrawPoint.zero, DrawPoint(x: 1, y: 0)],
      startBinding: ArrowBinding(
        elementId: _textId,
        anchor: DrawPoint(x: 0.5, y: 0.5),
      ),
      startIsSpecial: true,
    ),
  );

  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: [textElement, arrowElement]),
      selection: const SelectionState(selectedIds: {_textId}),
    ),
  );

  return base.copyWith(
    application: base.application.copyWith(
      interaction: const TextEditingState(
        elementId: _textId,
        draftData: TextData(text: 'before'),
        rect: textRect,
        isNew: false,
        opacity: 1,
        rotation: 0,
      ),
    ),
  );
}

ArrowData _arrowData(DefaultDrawStore store) {
  final element = store.state.domain.document.getElementById('arrow-1');
  expect(element, isNotNull);
  final data = element!.data;
  expect(data, isA<ArrowData>());
  return data as ArrowData;
}
