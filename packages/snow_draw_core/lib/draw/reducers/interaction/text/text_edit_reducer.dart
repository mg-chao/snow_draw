import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../core/dependency_interfaces.dart';
import '../../../elements/types/text/text_data.dart';
import '../../../elements/types/text/text_layout.dart';
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
  ) =>
      switch (action) {
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
      draftData =
          const TextData().withElementStyle(defaults) as TextData;
      rect = _initialTextRect(action.position, draftData);
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

    final nextData = interaction.draftData.copyWith(text: action.text);
    final nextRect = _resolveTextRect(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      currentRect: interaction.rect,
      data: nextData,
      autoResize: nextData.autoResize,
    );

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
      final nextDomain = state.domain.copyWith(
        document: state.domain.document.copyWith(elements: remainingElements),
      );
      final nextState = applySelectionChange(
        state.copyWith(domain: nextDomain),
        const {},
      );
      return nextState.copyWith(application: nextState.application.toIdle());
    }

    final nextData = interaction.draftData.copyWith(text: action.text);
    final nextRect = _resolveTextRect(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      currentRect: interaction.rect,
      data: nextData,
      autoResize: nextData.autoResize,
      allowShrinkHeight: nextData.autoResize,
    );

    if (interaction.isNew) {
      final element = ElementState(
        id: interaction.elementId,
        rect: nextRect,
        rotation: 0,
        opacity: interaction.opacity,
        zIndex: state.domain.document.elements.length,
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

    final elements = <ElementState>[];
    for (final element in state.domain.document.elements) {
      if (element.id != interaction.elementId) {
        elements.add(element);
        continue;
      }
      elements.add(element.copyWith(rect: nextRect, data: nextData));
    }

    final nextDomain = state.domain.copyWith(
      document: state.domain.document.copyWith(elements: elements),
    );
    final nextState = applySelectionChange(
      state.copyWith(domain: nextDomain),
      const {},
    );
    return nextState.copyWith(application: nextState.application.toIdle());
  }

  DrawState _cancelTextEdit(DrawState state) {
    if (state.application.interaction is! TextEditingState) {
      return state;
    }
    return state.copyWith(application: state.application.toIdle());
  }

  DrawRect _initialTextRect(DrawPoint position, TextData data) {
    final layout = layoutText(
      data: data,
      maxWidth: double.infinity,
    );
    final horizontalPadding = resolveTextLayoutHorizontalPadding(
      layout.lineHeight,
    );
    final width = layout.size.width + horizontalPadding * 2;
    final height = math.max(layout.size.height, layout.lineHeight);
    return DrawRect(
      minX: position.x,
      minY: position.y,
      maxX: position.x + width,
      maxY: position.y + height,
    );
  }

  DrawRect _resolveTextRect({
    required DrawPoint origin,
    required DrawRect currentRect,
    required TextData data,
    required bool autoResize,
    bool allowShrinkHeight = false,
  }) {
    final maxWidth = autoResize
        ? double.infinity
        : currentRect.width;
    final layout = layoutText(data: data, maxWidth: maxWidth);
    final horizontalPadding = resolveTextLayoutHorizontalPadding(
      layout.lineHeight,
    );
    final minHeight = math.max(layout.lineHeight, layout.size.height);

    final nextWidth = autoResize
        ? layout.size.width + horizontalPadding * 2
        : currentRect.width;
    // Always adjust height to match actual content during text editing
    final desiredHeight = minHeight;

    return DrawRect(
      minX: origin.x,
      minY: origin.y,
      maxX: origin.x + nextWidth,
      maxY: origin.y + desiredHeight,
    );
  }
}
