import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/types/text/text_editing_geometry.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_point.dart';
import '../core/arrow_binding_sync.dart';
import '../core/reducer_utils.dart';

DrawState handleRefreshAutoResizeTextLayoutsAfterFontLoad(
  DrawState state,
  RefreshAutoResizeTextLayoutsAfterFontLoad _,
  DrawContext context,
) {
  final document = state.domain.document;
  final selectedIds = state.domain.selection.selectedIds;
  final shouldRefreshSelectionOverlay = selectedIds.length > 1;
  final replacementsById = <String, ElementState>{};
  final changedBindableIds = <String>{};
  var refreshSelectionOverlay = false;

  for (final element in document.elements) {
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

    replacementsById[element.id] = element.copyWith(rect: nextRect);
    changedBindableIds.add(element.id);
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

  final hasDomainChanges = replacementsById.isNotEmpty;
  if (!hasDomainChanges && nextTextInteraction == null) {
    return state;
  }

  var mergedReplacementsById = replacementsById;
  List<String>? orderedElementIds;
  if (hasDomainChanges && changedBindableIds.isNotEmpty) {
    final bindingResolution = resolveArrowBindingsForChangedBindables(
      state: state,
      changedBindableIds: changedBindableIds,
      overlayUpdates: replacementsById,
      isBindingEnabled: context.config.snap.enableArrowBinding,
    );
    if (bindingResolution.updatedElements.isNotEmpty) {
      mergedReplacementsById = {
        ...replacementsById,
        ...bindingResolution.updatedElements,
      };
      if (shouldRefreshSelectionOverlay &&
          _hasSelectionGeometryChanges(
            selectedIds: selectedIds,
            originalElementsById: document.elementMap,
            updatesById: bindingResolution.updatedElements,
          )) {
        refreshSelectionOverlay = true;
      }
    }
    orderedElementIds = bindingResolution.orderedElementIds;
  }

  var nextState = state;
  if (hasDomainChanges) {
    nextState = nextState.copyWith(
      domain: nextState.domain.copyWith(
        document: document.copyWith(
          elements: applyElementReplacementsAndOrder(
            elements: document.elements,
            replacementsById: mergedReplacementsById,
            orderedElementIds: orderedElementIds,
          ),
        ),
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

bool _hasSelectionGeometryChanges({
  required Set<String> selectedIds,
  required Map<String, ElementState> originalElementsById,
  required Map<String, ElementState> updatesById,
}) {
  for (final id in selectedIds) {
    final original = originalElementsById[id];
    final updated = updatesById[id];
    if (original == null || updated == null) {
      continue;
    }
    if (original.rect != updated.rect ||
        original.rotation != updated.rotation) {
      return true;
    }
  }
  return false;
}
