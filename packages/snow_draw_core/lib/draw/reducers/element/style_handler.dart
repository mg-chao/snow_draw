import 'dart:math' as math;

import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../elements/core/element_style_updatable_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/types/text/text_layout.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/element_style.dart';

DrawState handleUpdateElementsStyle(
  DrawState state,
  UpdateElementsStyle action,
  DrawContext _,
) {
  final ids = action.elementIds.toSet();
  if (ids.isEmpty) {
    return state;
  }

  final styleUpdate = ElementStyleUpdate(
    color: action.color,
    fillColor: action.fillColor,
    strokeWidth: action.strokeWidth,
    strokeStyle: action.strokeStyle,
    fillStyle: action.fillStyle,
    cornerRadius: action.cornerRadius,
    fontSize: action.fontSize,
    fontFamily: action.fontFamily,
    textAlign: action.textAlign,
    verticalAlign: action.verticalAlign,
    textStrokeColor: action.textStrokeColor,
    textStrokeWidth: action.textStrokeWidth,
  );

  final elements = <ElementState>[];
  var domainChanged = false;
  var interactionChanged = false;
  TextEditingState? nextTextEdit;

  for (final element in state.domain.document.elements) {
    if (!ids.contains(element.id)) {
      elements.add(element);
      continue;
    }

    var next = element;
    final data = element.data;

    if (!styleUpdate.isEmpty && data is ElementStyleUpdatableData) {
      final updatedData = (data as ElementStyleUpdatableData).withStyleUpdate(
        styleUpdate,
      );
      if (updatedData != data) {
        next = next.copyWith(data: updatedData);
        if (data is TextData &&
            updatedData is TextData &&
            _shouldRelayoutText(styleUpdate)) {
          final nextRect = _resolveTextRect(
            origin: DrawPoint(x: next.rect.minX, y: next.rect.minY),
            currentRect: next.rect,
            data: updatedData,
            autoResize: updatedData.autoResize,
            allowShrinkHeight: true,
          );
          if (nextRect != next.rect) {
            next = next.copyWith(rect: nextRect);
          }
        }
        domainChanged = true;
      }
    }

    final opacity = action.opacity;
    if (opacity != null && opacity != element.opacity) {
      next = next.copyWith(opacity: opacity);
      domainChanged = true;
    }

    elements.add(next);
  }

  final interaction = state.application.interaction;
  if (interaction is TextEditingState &&
      ids.contains(interaction.elementId)) {
    nextTextEdit = _applyTextEditingStyleUpdate(
      interaction,
      styleUpdate,
      action.opacity,
    );
    interactionChanged = nextTextEdit != null;
  }

  if (!domainChanged && !interactionChanged) {
    return state;
  }

  final nextDomain = domainChanged
      ? state.domain.copyWith(
          document: state.domain.document.copyWith(elements: elements),
        )
      : state.domain;
  final nextApplication = interactionChanged
      ? state.application.copyWith(interaction: nextTextEdit)
      : state.application;

  return state.copyWith(domain: nextDomain, application: nextApplication);
}

TextEditingState? _applyTextEditingStyleUpdate(
  TextEditingState interaction,
  ElementStyleUpdate styleUpdate,
  double? opacity,
) {
  var nextData = interaction.draftData;
  var nextRect = interaction.rect;
  var nextOpacity = interaction.opacity;
  var changed = false;

  if (!styleUpdate.isEmpty) {
    final updatedData = interaction.draftData.withStyleUpdate(styleUpdate);
    if (updatedData is TextData && updatedData != interaction.draftData) {
      nextData = updatedData;
      changed = true;
      nextRect = _resolveTextRect(
        origin: DrawPoint(
          x: interaction.rect.minX,
          y: interaction.rect.minY,
        ),
        currentRect: interaction.rect,
        data: nextData,
        autoResize: nextData.autoResize,
        allowShrinkHeight: true,
      );
      if (nextRect != interaction.rect) {
        changed = true;
      }
    }
  }

  if (opacity != null && opacity != interaction.opacity) {
    nextOpacity = opacity;
    changed = true;
  }

  if (!changed) {
    return null;
  }

  return interaction.copyWith(
    draftData: nextData,
    rect: nextRect,
    opacity: nextOpacity,
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
  final shouldShrinkHeight = autoResize || allowShrinkHeight;
  final desiredHeight = shouldShrinkHeight
      ? minHeight
      : math.max(currentRect.height, minHeight);

  return DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + nextWidth,
    maxY: origin.y + desiredHeight,
  );
}

bool _shouldRelayoutText(ElementStyleUpdate update) =>
    update.fontSize != null || update.fontFamily != null;
