import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/types/text/text_editing_geometry.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_point.dart';
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

    final nextRect = resolveAutoResizeTextEditingRect(
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
    final nextRect = resolveAutoResizeTextEditingRect(
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
