import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('FinishTextEdit history consistency', () {
    test('UpdateTextEdit ignores repeated text payloads', () async {
      final store = _createStore(
        initialState: _stateWithActiveTextEdit(
          elementId: 'text-1',
          initialText: 'before',
          draftText: 'before',
        ),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(const UpdateTextEdit(text: 'before'));

      expect(store.state, same(before));
    });

    test(
      'undo restores text content when action payload matches session',
      () async {
        final store = _createStore(
          initialState: _stateWithActiveTextEdit(
            elementId: 'text-1',
            initialText: 'before',
            draftText: 'before',
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'text-1',
            text: 'after',
            isNew: false,
          ),
        );

        expect(_textOf(store, 'text-1'), 'after');
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_textOf(store, 'text-1'), 'before');
      },
    );

    test(
      'undo still restores text when action payload elementId is stale',
      () async {
        final store = _createStore(
          initialState: _stateWithActiveTextEdit(
            elementId: 'text-1',
            initialText: 'before',
            draftText: 'before',
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'stale-id',
            text: 'after',
            isNew: false,
          ),
        );

        expect(_textOf(store, 'text-1'), 'after');
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_textOf(store, 'text-1'), 'before');
      },
    );

    test(
      'undo removes created text when action payload marks session as existing',
      () async {
        final store = _createStore(
          initialState: _stateWithNewTextEdit(
            elementId: 'text-new',
            draftText: '',
          ),
        );
        addTearDown(store.dispose);

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
        final store = _createStore(
          initialState: _stateWithActiveTextEdit(
            elementId: 'text-1',
            initialText: 'before',
            draftText: 'before',
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(elementId: 'stale-id', text: '   ', isNew: true),
        );

        expect(_elementExists(store, 'text-1'), isFalse);
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());

        expect(_textOf(store, 'text-1'), 'before');
      },
    );

    test(
      'finishing unchanged text keeps the document snapshot intact',
      () async {
        final alignedRect = _autoResizeTextRect('before');
        final store = _createStore(
          initialState: _stateWithActiveTextEdit(
            elementId: 'text-1',
            initialText: 'before',
            draftText: 'before',
            rect: alignedRect,
          ),
        );
        addTearDown(store.dispose);

        final before = store.state;

        await store.dispatch(
          const FinishTextEdit(
            elementId: 'text-1',
            text: 'before',
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
            data: TextData(text: initialText),
          ),
        ],
      ),
      selection: SelectionState(selectedIds: {elementId}),
    ),
  );

  final interaction = TextEditingState(
    elementId: elementId,
    draftData: TextData(text: draftText),
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
  final element = store.state.domain.document.getElementById(elementId);
  final data = element?.data;
  if (data is! TextData) {
    return '';
  }
  return data.text;
}

bool _elementExists(DefaultDrawStore store, String elementId) =>
    store.state.domain.document.getElementById(elementId) != null;

DrawRect _autoResizeTextRect(
  String text, {
  double originX = 10,
  double originY = 10,
}) {
  final data = TextData(text: text);
  final layout = layoutText(data: data, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final width = layout.size.width + horizontalPadding * 2;
  final height = layout.size.height > layout.lineHeight
      ? layout.size.height
      : layout.lineHeight;
  return DrawRect(
    minX: originX,
    minY: originY,
    maxX: originX + width,
    maxY: originY + height,
  );
}
