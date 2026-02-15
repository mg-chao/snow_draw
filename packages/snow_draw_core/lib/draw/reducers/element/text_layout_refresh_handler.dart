import 'dart:math' as math;

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/types/text/text_layout.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../core/reducer_utils.dart';

DrawState handleRefreshAutoResizeTextLayoutsAfterFontLoad(
  DrawState state,
  RefreshAutoResizeTextLayoutsAfterFontLoad _,
  ElementReducerDeps _,
) {
  final document = state.domain.document;
  final selectedIds = state.domain.selection.selectedIds;
  final shouldTrackOverlayRefresh = selectedIds.length > 1;

  List<ElementState>? nextElements;
  var domainChanged = false;
  var selectedGeometryChanged = false;

  for (var index = 0; index < document.elements.length; index++) {
    final element = document.elements[index];
    final data = element.data;
    if (data is! TextData || !data.autoResize) {
      continue;
    }

    final nextRect = _resolveAutoResizeTextRect(
      origin: DrawPoint(x: element.rect.minX, y: element.rect.minY),
      data: data,
    );
    if (nextRect == element.rect) {
      continue;
    }

    domainChanged = true;
    nextElements ??= [...document.elements];
    nextElements[index] = element.copyWith(rect: nextRect);
    if (shouldTrackOverlayRefresh && selectedIds.contains(element.id)) {
      selectedGeometryChanged = true;
    }
  }

  TextEditingState? nextTextInteraction;
  var interactionChanged = false;
  final interaction = state.application.interaction;
  if (interaction is TextEditingState && interaction.draftData.autoResize) {
    final nextRect = _resolveAutoResizeTextRect(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      data: interaction.draftData,
    );
    if (nextRect != interaction.rect) {
      nextTextInteraction = interaction.copyWith(rect: nextRect);
      interactionChanged = true;
      if (shouldTrackOverlayRefresh &&
          selectedIds.contains(interaction.elementId)) {
        selectedGeometryChanged = true;
      }
    }
  }

  if (!domainChanged && !interactionChanged) {
    return state;
  }

  var nextState = state;
  if (domainChanged && nextElements != null) {
    nextState = state.copyWith(
      domain: state.domain.copyWith(
        document: document.copyWith(elements: nextElements),
      ),
    );
  }
  if (interactionChanged && nextTextInteraction != null) {
    nextState = nextState.copyWith(
      application: nextState.application.copyWith(
        interaction: nextTextInteraction,
      ),
    );
  }

  if (!selectedGeometryChanged) {
    return nextState;
  }

  return applySelectionChange(
    nextState,
    selectedIds,
    forceRefreshOverlay: true,
  );
}

DrawRect _resolveAutoResizeTextRect({
  required DrawPoint origin,
  required TextData data,
}) {
  final layout = layoutText(data: data, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final minHeight = math.max(layout.lineHeight, layout.size.height);
  final nextWidth = layout.size.width + horizontalPadding * 2;

  return DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + nextWidth,
    maxY: origin.y + minHeight,
  );
}
