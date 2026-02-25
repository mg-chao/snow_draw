import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
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
  DrawContext context,
) {
  final document = state.domain.document;
  final selectedIds = state.domain.selection.selectedIds;
  final shouldRefreshSelectionOverlay = selectedIds.length > 1;

  List<ElementState>? nextElements;
  var refreshSelectionOverlay = false;

  for (var index = 0; index < document.elements.length; index++) {
    final element = document.elements[index];
    final data = element.data;
    if (data is! TextData || !data.autoResize) {
      continue;
    }

    final nextRect = resolveAutoResizeTextEditingRect(
      origin: DrawPoint(x: element.rect.minX, y: element.rect.minY),
      data: data,
      textMetricsService: context.textMetricsService,
    );
    if (nextRect == element.rect) {
      continue;
    }

    nextElements ??= [...document.elements];
    nextElements[index] = element.copyWith(rect: nextRect);
    if (shouldRefreshSelectionOverlay && selectedIds.contains(element.id)) {
      refreshSelectionOverlay = true;
    }
  }

  TextEditingState? nextTextInteraction;
  final interaction = state.application.interaction;
  if (interaction is TextEditingState && interaction.draftData.autoResize) {
    final nextRect = resolveAutoResizeTextEditingRect(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      data: interaction.draftData,
      textMetricsService: context.textMetricsService,
    );
    if (nextRect != interaction.rect) {
      nextTextInteraction = interaction.copyWith(rect: nextRect);
      if (shouldRefreshSelectionOverlay &&
          selectedIds.contains(interaction.elementId)) {
        refreshSelectionOverlay = true;
      }
    }
  }

  if (nextElements == null && nextTextInteraction == null) {
    return state;
  }

  var nextState = state;
  if (nextElements != null) {
    nextState = nextState.copyWith(
      domain: nextState.domain.copyWith(
        document: document.copyWith(elements: nextElements),
      ),
    );
  }
  if (nextTextInteraction != null) {
    nextState = nextState.copyWith(
      application: nextState.application.copyWith(
        interaction: nextTextInteraction,
      ),
    );
  }

  if (!refreshSelectionOverlay) {
    return nextState;
  }

  return applySelectionChange(
    nextState,
    selectedIds,
    forceRefreshOverlay: true,
  );
}
