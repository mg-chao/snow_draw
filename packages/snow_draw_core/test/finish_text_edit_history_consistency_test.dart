import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_editing_geometry.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

const _textId = 'text-1';
const _baseText = 'before';

void main() {
  group('FinishTextEdit history consistency', () {
    test('UpdateTextEdit ignores repeated text payloads', () async {
      final store = _storeWithActiveTextEdit();

      final before = store.state;

      await store.dispatch(const UpdateTextEdit(text: _baseText));

      expect(store.state, same(before));
    });

    test('UpdateTextEdit applies provided draft rect override', () async {
      final store = _storeWithActiveTextEdit();

      const overrideRect = DrawRect(minX: 4, minY: 5, maxX: 104, maxY: 48);
      await store.dispatch(
        const UpdateTextEdit(text: 'after', rect: overrideRect),
      );

      final interaction = store.state.application.interaction;
      expect(interaction, isA<TextEditingState>());
      final editing = interaction as TextEditingState;
      expect(editing.draftData.text, 'after');
      expect(editing.rect, overrideRect);
    });

    test(
      'UpdateTextEdit shrinks fixed-width text edit bounds to fit content',
      () async {
        const initialRect = DrawRect(minX: 10, minY: 10, maxX: 210, maxY: 210);
        final store = _storeWithActiveTextEdit(
          initialText: 'seed',
          draftText: 'seed',
          rect: initialRect,
          autoResize: false,
        );

        const nextText = 'short';
        const nextData = TextData(text: nextText, autoResize: false);
        final expectedRect = _fixedWidthTextRect(
          currentRect: initialRect,
          data: nextData,
        );

        await store.dispatch(const UpdateTextEdit(text: nextText));

        final interaction = store.state.application.interaction;
        expect(interaction, isA<TextEditingState>());
        final editing = interaction as TextEditingState;
        expect(editing.rect, equals(expectedRect));
        expect(editing.rect.height, lessThan(initialRect.height));
      },
    );

    test(
      'FinishTextEdit persists shrunk bounds for fixed-width text elements',
      () async {
        const initialRect = DrawRect(minX: 10, minY: 10, maxX: 210, maxY: 210);
        final store = _storeWithActiveTextEdit(
          initialText: 'seed',
          draftText: 'seed',
          rect: initialRect,
          autoResize: false,
        );

        const nextText = 'short';
        const nextData = TextData(text: nextText, autoResize: false);
        final expectedRect = _fixedWidthTextRect(
          currentRect: initialRect,
          data: nextData,
        );

        await store.dispatch(
          const FinishTextEdit(
            elementId: _textId,
            text: nextText,
            isNew: false,
          ),
        );

        final element = store.state.domain.document.getElementById(_textId);
        expect(element, isNotNull);
        expect(element!.rect, equals(expectedRect));
      },
    );

    test('undo restores text content for finished edits', () async {
      final store = _storeWithActiveTextEdit();

      await store.dispatch(
        const FinishTextEdit(elementId: _textId, text: 'after', isNew: false),
      );

      expect(_textOf(store, _textId), 'after');
      expect(store.canUndo, isTrue);

      await store.dispatch(const Undo());

      expect(_textOf(store, _textId), _baseText);
    });

    test(
      'undo still restores text when action payload elementId is stale',
      () async {
        final store = _storeWithActiveTextEdit();

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'stale-id',
            text: 'after',
            isNew: false,
          ),
        );

        expect(_textOf(store, _textId), 'after');
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_textOf(store, _textId), _baseText);
      },
    );

    test(
      'undo removes created text when action payload marks session as existing',
      () async {
        final store = _storeWithNewTextEdit(
          elementId: 'text-new',
          draftText: '',
        );

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'stale-id',
            text: 'created',
            isNew: false,
          ),
        );

        expect(_textOf(store, 'text-new'), 'created');
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_elementExists(store, 'text-new'), isFalse);
      },
    );

    test(
      'undo restores deleted text when action payload marks session as new',
      () async {
        final store = _storeWithActiveTextEdit();

        await store.dispatch(
          const FinishTextEdit(elementId: 'stale-id', text: '   ', isNew: true),
        );

        expect(_elementExists(store, _textId), isFalse);
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_textOf(store, _textId), _baseText);
      },
    );

    test('new empty text finish does not create a history entry', () async {
      final store = _storeWithNewTextEdit(elementId: 'text-new', draftText: '');

      final before = store.state.domain.document;

      await store.dispatch(
        const FinishTextEdit(elementId: 'stale-id', text: '   ', isNew: true),
      );

      expect(store.state.domain.document, same(before));
      expect(store.canUndo, isFalse);
    });

    test(
      'finishing unchanged text keeps the document snapshot intact',
      () async {
        final alignedRect = _autoResizeTextRect(_baseText);
        final store = _storeWithActiveTextEdit(rect: alignedRect);

        final before = store.state;

        await store.dispatch(
          const FinishTextEdit(
            elementId: _textId,
            text: _baseText,
            isNew: false,
          ),
        );

        expect(store.state.application.isIdle, isTrue);
        expect(store.state.domain.selection.selectedIds, isEmpty);
        expect(store.state.domain.document, same(before.domain.document));
      },
    );
  });
}

DefaultDrawStore _storeWithActiveTextEdit({
  String elementId = _textId,
  String initialText = _baseText,
  String draftText = _baseText,
  DrawRect? rect,
  bool autoResize = true,
}) {
  final store = _createStore(
    initialState: _stateWithActiveTextEdit(
      elementId: elementId,
      initialText: initialText,
      draftText: draftText,
      rect: rect,
      autoResize: autoResize,
    ),
  );
  addTearDown(store.dispose);
  return store;
}

DefaultDrawStore _storeWithNewTextEdit({
  required String elementId,
  required String draftText,
}) {
  final store = _createStore(
    initialState: _stateWithNewTextEdit(
      elementId: elementId,
      draftText: draftText,
    ),
  );
  addTearDown(store.dispose);
  return store;
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithActiveTextEdit({
  required String elementId,
  required String initialText,
  required String draftText,
  DrawRect? rect,
  bool autoResize = true,
}) {
  final resolvedRect = rect ?? _autoResizeTextRect(initialText);
  final initial = DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: [
          ElementState(
            id: elementId,
            rect: resolvedRect,
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: TextData(text: initialText, autoResize: autoResize),
          ),
        ],
      ),
      selection: SelectionState(selectedIds: {elementId}),
    ),
  );

  final interaction = TextEditingState(
    elementId: elementId,
    draftData: TextData(text: draftText, autoResize: autoResize),
    rect: resolvedRect,
    isNew: false,
    opacity: 1,
    rotation: 0,
  );

  return initial.copyWith(
    application: initial.application.copyWith(interaction: interaction),
  );
}

DrawState _stateWithNewTextEdit({
  required String elementId,
  required String draftText,
}) {
  const rect = DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 60);
  final initial = DrawState();
  final interaction = TextEditingState(
    elementId: elementId,
    draftData: TextData(text: draftText),
    rect: rect,
    isNew: true,
    opacity: 1,
    rotation: 0,
  );

  return initial.copyWith(
    application: initial.application.copyWith(interaction: interaction),
  );
}

String _textOf(DefaultDrawStore store, String elementId) {
  final element = store.state.domain.document.getElementById(elementId)!;
  return (element.data as TextData).text;
}

bool _elementExists(DefaultDrawStore store, String elementId) =>
    store.state.domain.document.getElementById(elementId) != null;

DrawRect _autoResizeTextRect(
  String text, {
  double originX = 10,
  double originY = 10,
}) => resolveAutoResizeTextEditingRect(
  origin: DrawPoint(x: originX, y: originY),
  data: TextData(text: text),
);

DrawRect _fixedWidthTextRect({
  required DrawRect currentRect,
  required TextData data,
}) => resolveTextEditingRect(
  origin: DrawPoint(x: currentRect.minX, y: currentRect.minY),
  currentRect: currentRect,
  data: data,
  allowShrinkHeight: true,
);
