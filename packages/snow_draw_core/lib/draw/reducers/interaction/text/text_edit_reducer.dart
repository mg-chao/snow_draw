import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../core/dependency_interfaces.dart';
import '../../../elements/types/arrow/arrow_like_data.dart';
import '../../../elements/types/serial_number/serial_number_data.dart';
import '../../../elements/types/text/text_data.dart';
import '../../../elements/types/text/text_editing_geometry.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/reducer_utils.dart';

/// Reducer for text editing interactions.
@immutable
class TextEditReducer {
  const TextEditReducer();

  DrawState? reduce(
    DrawState state,
    DrawAction action,
    TextEditReducerDeps context,
  ) => switch (action) {
    final StartTextEdit a => _startTextEdit(state, a, context),
    final UpdateTextEdit a => _updateTextEdit(state, a),
    final FinishTextEdit a => _finishTextEdit(state, a, context),
    CancelTextEdit _ => _cancelTextEdit(state),
    _ => null,
  };

  DrawState _startTextEdit(
    DrawState state,
    StartTextEdit action,
    TextEditReducerDeps context,
  ) {
    if (state.application.interaction is TextEditingState) {
      return state;
    }

    final elementId = action.elementId;
    TextData draftData;
    DrawRect rect;
    bool isNew;
    String resolvedId;
    double opacity;
    double rotation;

    if (elementId != null) {
      final element = state.domain.document.getElementById(elementId);
      if (element == null || element.data is! TextData) {
        return state;
      }
      draftData = element.data as TextData;
      rect = element.rect;
      opacity = element.opacity;
      rotation = element.rotation;
      isNew = false;
      resolvedId = elementId;
    } else {
      final defaults = context.config.textStyle;
      draftData = const TextData().withElementStyle(defaults) as TextData;
      rect = resolveInitialTextEditingRect(
        position: action.position,
        data: draftData,
      );
      opacity = defaults.opacity;
      rotation = 0;
      isNew = true;
      resolvedId = context.idGenerator();
    }

    final selectionIds = isNew ? const <String>{} : {resolvedId};
    final nextState = applySelectionChange(state, selectionIds);

    return nextState.copyWith(
      application: nextState.application.copyWith(
        interaction: TextEditingState(
          elementId: resolvedId,
          draftData: draftData,
          rect: rect,
          isNew: isNew,
          opacity: opacity,
          rotation: rotation,
          initialCursorPosition: action.position,
        ),
      ),
    );
  }

  DrawState _updateTextEdit(DrawState state, UpdateTextEdit action) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return state;
    }
    if (action.text == interaction.draftData.text && action.rect == null) {
      return state;
    }

    final nextData = interaction.draftData.copyWith(text: action.text);
    final nextRect =
        action.rect ??
        resolveTextEditingRect(
          origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
          currentRect: interaction.rect,
          data: nextData,
          allowShrinkHeight: true,
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
    TextEditReducerDeps context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return state;
    }

    final trimmed = action.text.trim();
    if (trimmed.isEmpty) {
      if (interaction.isNew) {
        return state.copyWith(application: state.application.toIdle());
      }

      final remainingElements = state.domain.document.elements
          .where((element) => element.id != interaction.elementId)
          .toList();
      final updatedElements = <ElementState>[];
      for (final element in remainingElements) {
        final serialUpdate = _resolveSerialUnbindUpdate(
          element: element,
          deletedTextId: interaction.elementId,
        );
        if (serialUpdate != null) {
          updatedElements.add(serialUpdate);
          continue;
        }

        final arrowUpdate = _resolveArrowUnbindUpdate(
          element: element,
          deletedTextId: interaction.elementId,
        );
        updatedElements.add(arrowUpdate ?? element);
      }
      final nextDomain = state.domain.copyWith(
        document: state.domain.document.copyWith(elements: updatedElements),
      );
      final nextState = applySelectionChange(
        state.copyWith(domain: nextDomain),
        const {},
      );
      return nextState.copyWith(application: nextState.application.toIdle());
    }

    final nextData = interaction.draftData.copyWith(text: action.text);
    final nextRect = resolveTextEditingRect(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      currentRect: interaction.rect,
      data: nextData,
      allowShrinkHeight: true,
    );

    if (interaction.isNew) {
      final element = ElementState(
        id: interaction.elementId,
        rect: nextRect,
        rotation: 0,
        opacity: interaction.opacity,
        zIndex: resolveNextZIndex(state.domain.document.elements),
        data: nextData,
      );
      final nextElements = [...state.domain.document.elements, element];
      final nextDomain = state.domain.copyWith(
        document: state.domain.document.copyWith(elements: nextElements),
      );
      final nextState = applySelectionChange(
        state.copyWith(domain: nextDomain),
        const {},
      );
      return nextState.copyWith(application: nextState.application.toIdle());
    }

    final elements = state.domain.document.elements;
    List<ElementState>? nextElements;
    for (var index = 0; index < elements.length; index++) {
      final currentElement = elements[index];
      if (currentElement.id != interaction.elementId) {
        continue;
      }
      if (currentElement.rect == nextRect && currentElement.data == nextData) {
        continue;
      }
      nextElements ??= [...elements];
      nextElements[index] = currentElement.copyWith(
        rect: nextRect,
        data: nextData,
      );
    }

    var nextBaseState = state;
    if (nextElements != null) {
      nextBaseState = state.copyWith(
        domain: state.domain.copyWith(
          document: state.domain.document.copyWith(elements: nextElements),
        ),
      );
    }

    final nextState = applySelectionChange(nextBaseState, const {});
    return nextState.copyWith(application: nextState.application.toIdle());
  }

  DrawState _cancelTextEdit(DrawState state) {
    if (state.application.interaction is! TextEditingState) {
      return state;
    }
    return state.copyWith(application: state.application.toIdle());
  }

  ElementState? _resolveSerialUnbindUpdate({
    required ElementState element,
    required String deletedTextId,
  }) {
    final data = element.data;
    if (data is! SerialNumberData || data.textElementId != deletedTextId) {
      return null;
    }
    return element.copyWith(data: data.copyWith(textElementId: null));
  }

  ElementState? _resolveArrowUnbindUpdate({
    required ElementState element,
    required String deletedTextId,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      return null;
    }

    final startBinding = data.startBinding;
    final endBinding = data.endBinding;
    final clearStart =
        startBinding != null && startBinding.elementId == deletedTextId;
    final clearEnd =
        endBinding != null && endBinding.elementId == deletedTextId;
    if (!clearStart && !clearEnd) {
      return null;
    }

    final nextData = data.copyWith(
      startBinding: clearStart ? null : startBinding,
      endBinding: clearEnd ? null : endBinding,
      startIsSpecial: clearStart ? null : data.startIsSpecial,
      endIsSpecial: clearEnd ? null : data.endIsSpecial,
    );
    return element.copyWith(data: nextData);
  }
}
