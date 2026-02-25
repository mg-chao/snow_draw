import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../core/draw_context.dart';
import '../../../edit/apply/edit_apply.dart';
import '../../../elements/types/serial_number/serial_number_dependencies.dart';
import '../../../elements/types/text/text_data.dart';
import '../../../elements/types/text/text_editing_geometry.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/reducer_utils.dart';

typedef _TextEditSession = ({
  String elementId,
  TextData draftData,
  DrawRect rect,
  bool isNew,
  double opacity,
  double rotation,
});

/// Reducer for text editing interactions.
@immutable
class TextEditReducer {
  const TextEditReducer();

  DrawState? reduce(DrawState state, DrawAction action, DrawContext context) =>
      switch (action) {
        final StartTextEdit a => _startTextEdit(state, a, context),
        final UpdateTextEdit a => _updateTextEdit(state, a, context),
        final FinishTextEdit a => _finishTextEdit(state, a, context),
        CancelTextEdit _ => _cancelTextEdit(state),
        _ => null,
      };

  DrawState _startTextEdit(
    DrawState state,
    StartTextEdit action,
    DrawContext context,
  ) {
    if (state.application.interaction is TextEditingState) {
      return state;
    }

    final session = _resolveStartSession(state, action, context);
    if (session == null) {
      return state;
    }

    final nextState = applySelectionChange(
      state,
      session.isNew ? const <String>{} : {session.elementId},
    );

    return nextState.copyWith(
      application: nextState.application.copyWith(
        interaction: TextEditingState(
          elementId: session.elementId,
          draftData: session.draftData,
          rect: session.rect,
          isNew: session.isNew,
          opacity: session.opacity,
          rotation: session.rotation,
          initialCursorPosition: action.position,
        ),
      ),
    );
  }

  _TextEditSession? _resolveStartSession(
    DrawState state,
    StartTextEdit action,
    DrawContext context,
  ) => switch (action.elementId) {
    final String elementId => _resolveExistingSession(state, elementId),
    null => _resolveNewSession(action, context),
  };

  _TextEditSession? _resolveExistingSession(DrawState state, String elementId) {
    final element = state.domain.document.getElementById(elementId);
    final data = element?.data;
    if (element == null || data is! TextData) {
      return null;
    }
    return (
      elementId: element.id,
      draftData: data,
      rect: element.rect,
      isNew: false,
      opacity: element.opacity,
      rotation: element.rotation,
    );
  }

  _TextEditSession _resolveNewSession(
    StartTextEdit action,
    DrawContext context,
  ) {
    final defaults = context.config.textStyle;
    final draftData = const TextData().withElementStyle(defaults) as TextData;
    return (
      elementId: context.idGenerator(),
      draftData: draftData,
      rect: resolveInitialTextEditingRect(
        position: action.position,
        data: draftData,
        textMetricsService: context.textMetricsService,
      ),
      isNew: true,
      opacity: defaults.opacity,
      rotation: 0,
    );
  }

  DrawState _updateTextEdit(
    DrawState state,
    UpdateTextEdit action,
    DrawContext context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return state;
    }

    final textUnchanged = action.text == interaction.draftData.text;
    if (textUnchanged && action.rect == null) {
      return state;
    }

    final nextData = textUnchanged
        ? interaction.draftData
        : interaction.draftData.copyWith(text: action.text);
    final nextRect =
        action.rect ??
        _resolveTextDraftRect(
          currentRect: interaction.rect,
          data: nextData,
          context: context,
        );
    if (nextData == interaction.draftData && nextRect == interaction.rect) {
      return state;
    }

    return state.copyWith(
      application: state.application.copyWith(
        interaction: interaction.copyWith(draftData: nextData, rect: nextRect),
      ),
    );
  }

  DrawState _finishTextEdit(
    DrawState state,
    FinishTextEdit action,
    DrawContext context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return state;
    }

    if (action.text.trim().isEmpty) {
      return _finishEmptyText(state, interaction);
    }

    return _commitTextDraft(
      state: state,
      interaction: interaction,
      rawText: action.text,
      context: context,
    );
  }

  DrawState _finishEmptyText(DrawState state, TextEditingState interaction) =>
      interaction.isNew
      ? _toIdle(state)
      : _deleteExistingText(state, interaction);

  DrawState _commitTextDraft({
    required DrawState state,
    required TextEditingState interaction,
    required String rawText,
    required DrawContext context,
  }) {
    final nextData = interaction.draftData.copyWith(text: rawText);
    final nextRect = _resolveTextDraftRect(
      currentRect: interaction.rect,
      data: nextData,
      context: context,
    );

    return interaction.isNew
        ? _createTextElement(state, interaction, nextData, nextRect)
        : _updateTextElement(state, interaction, nextData, nextRect);
  }

  DrawState _createTextElement(
    DrawState state,
    TextEditingState interaction,
    TextData data,
    DrawRect rect,
  ) {
    final element = ElementState(
      id: interaction.elementId,
      rect: rect,
      rotation: 0,
      opacity: interaction.opacity,
      zIndex: resolveNextZIndex(state.domain.document.elements),
      data: data,
    );

    final nextState = state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(
          elements: [...state.domain.document.elements, element],
        ),
      ),
    );
    return _finishTextEditing(nextState);
  }

  DrawState _updateTextElement(
    DrawState state,
    TextEditingState interaction,
    TextData data,
    DrawRect rect,
  ) {
    final document = state.domain.document;
    final currentElement = document.getElementById(interaction.elementId);
    if (currentElement == null) {
      return _finishTextEditing(state);
    }
    if (currentElement.rect == rect && currentElement.data == data) {
      return _finishTextEditing(state);
    }
    final nextElements = EditApply.replaceElementsById(
      elements: document.elements,
      replacementsById: {
        interaction.elementId: currentElement.copyWith(rect: rect, data: data),
      },
    );

    final nextState = state.copyWith(
      domain: state.domain.copyWith(
        document: document.copyWith(elements: nextElements),
      ),
    );
    return _finishTextEditing(nextState);
  }

  DrawState _deleteExistingText(DrawState state, TextEditingState interaction) {
    final nextElements = _removeTextElementAndUnbindReferences(
      elements: state.domain.document.elements,
      deletedTextId: interaction.elementId,
    );
    final nextState = nextElements == null
        ? state
        : state.copyWith(
            domain: state.domain.copyWith(
              document: state.domain.document.copyWith(elements: nextElements),
            ),
          );
    return _finishTextEditing(nextState);
  }

  List<ElementState>? _removeTextElementAndUnbindReferences({
    required List<ElementState> elements,
    required String deletedTextId,
  }) {
    final deletedIds = <String>{deletedTextId};
    final nextElements = <ElementState>[];
    var changed = false;

    for (final element in elements) {
      if (element.id == deletedTextId) {
        changed = true;
        continue;
      }

      final updatedElement = clearElementDependenciesForIds(
        element: element,
        targetIds: deletedIds,
      );

      if (updatedElement != element) {
        changed = true;
      }
      nextElements.add(updatedElement);
    }

    return changed ? nextElements : null;
  }

  DrawState _cancelTextEdit(DrawState state) {
    if (state.application.interaction is! TextEditingState) {
      return state;
    }
    return _toIdle(state);
  }

  DrawRect _resolveTextDraftRect({
    required DrawRect currentRect,
    required TextData data,
    required DrawContext context,
  }) => resolveTextEditingRect(
    origin: DrawPoint(x: currentRect.minX, y: currentRect.minY),
    currentRect: currentRect,
    data: data,
    textMetricsService: context.textMetricsService,
    allowShrinkHeight: true,
  );

  DrawState _toIdle(DrawState state) =>
      state.copyWith(application: state.application.toIdle());

  DrawState _finishTextEditing(DrawState state) =>
      _toIdle(applySelectionChange(state, const <String>{}));
}
