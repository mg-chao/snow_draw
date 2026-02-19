import 'package:meta/meta.dart';

import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/elements/types/arrow/arrow_like_data.dart';
import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/elements/types/highlight/highlight_data.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import 'lightweight_line_edit_state_change.dart';
import 'serial_number_interaction_classifier.dart';

const _maxLocalizedPreviewElementCount = 24;

/// Dynamic-scene optimization plan for edit previews.
///
/// When present, the static painter hides [staticHiddenElementIds] while the
/// dynamic painter renders [optimizedElementIds] plus overlapping occluders.
@immutable
class DynamicSceneOptimizationPlan {
  DynamicSceneOptimizationPlan({
    required Set<String> optimizedElementIds,
    required Set<String> staticHiddenElementIds,
  }) : optimizedElementIds = Set<String>.unmodifiable(optimizedElementIds),
       staticHiddenElementIds = Set<String>.unmodifiable(
         staticHiddenElementIds,
       );

  factory DynamicSceneOptimizationPlan.single(String elementId) =>
      DynamicSceneOptimizationPlan(
        optimizedElementIds: {elementId},
        staticHiddenElementIds: {elementId},
      );

  final Set<String> optimizedElementIds;
  final Set<String> staticHiddenElementIds;
}

/// Resolves localized dynamic-scene optimization for the current [view].
///
/// Returns `null` when the interaction should keep using the regular dynamic
/// layer split.
DynamicSceneOptimizationPlan? resolveDynamicSceneOptimizationPlan({
  required DrawStateView view,
}) {
  final textEditingPlan = _resolveTextEditingOptimizationPlan(view);
  if (textEditingPlan != null) {
    return textEditingPlan;
  }

  final lightweightLinePlan = _resolveLightweightLineOptimizationPlan(view);
  if (lightweightLinePlan != null) {
    return lightweightLinePlan;
  }

  final arrowPointPlan = _resolveArrowPointOptimizationPlan(view);
  if (arrowPointPlan != null) {
    return arrowPointPlan;
  }

  final serialPlan = _resolveSerialNumberOptimizationPlan(view);
  if (serialPlan != null) {
    return serialPlan;
  }

  final highlightPlan = _resolveHighlightEditOptimizationPlan(view);
  if (highlightPlan != null) {
    return highlightPlan;
  }

  return _resolveSingleSelectionEditOptimizationPlan(view);
}

DynamicSceneOptimizationPlan? _resolveLightweightLineOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  final document = view.state.domain.document;
  if (!isLightweightLineEditingInteraction(
    interaction: interaction,
    document: document,
  )) {
    return null;
  }
  if (interaction is! EditingState) {
    return null;
  }

  final selectedIds = interaction.context.selectedIdsAtStart;
  if (selectedIds.isEmpty ||
      selectedIds.length > _maxLocalizedPreviewElementCount) {
    return null;
  }

  final previewElementsById = view.previewElementsById;
  final candidateIds = <String>{};
  for (final elementId in selectedIds) {
    final effective =
        previewElementsById[elementId] ?? document.getElementById(elementId);
    if (effective == null || _isBlendSensitiveElement(effective)) {
      return null;
    }
    candidateIds.add(elementId);
  }

  if (candidateIds.isEmpty) {
    return null;
  }

  final orderIndex = _resolveLowestOrderIndex(
    document: document,
    elementIds: candidateIds,
  );
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan(
    optimizedElementIds: candidateIds,
    staticHiddenElementIds: candidateIds,
  );
}

DynamicSceneOptimizationPlan? _resolveTextEditingOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  if (interaction is! TextEditingState || interaction.isNew) {
    return null;
  }

  // Text editing mutates a single preview element every keystroke. Keeping the
  // dynamic scene localized to that element avoids rebuilding all higher
  // z-index elements on each frame.
  final selectedIds = view.selectedIds;
  if (selectedIds.isNotEmpty &&
      (selectedIds.length != 1 ||
          !selectedIds.contains(interaction.elementId))) {
    return null;
  }

  final document = view.state.domain.document;
  final persisted = document.getElementById(interaction.elementId);
  final preview = view.previewElementsById[interaction.elementId];
  if (persisted == null ||
      persisted.data is! TextData ||
      preview == null ||
      preview.data is! TextData) {
    return null;
  }

  final orderIndex = document.getOrderIndex(interaction.elementId);
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan.single(interaction.elementId);
}

DynamicSceneOptimizationPlan? _resolveArrowPointOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  if (interaction is! EditingState ||
      interaction.context is! ArrowPointEditContext) {
    return null;
  }

  final context = interaction.context as ArrowPointEditContext;
  final elementId = context.elementId;
  if (view.selectedIds.length != 1 || !view.selectedIds.contains(elementId)) {
    return null;
  }

  final preview = view.previewElementsById[elementId];
  final document = view.state.domain.document;
  final element = document.getElementById(elementId);
  if (element == null || element.data is! ArrowLikeData) {
    return null;
  }
  if (preview != null && preview.data is! ArrowLikeData) {
    return null;
  }

  final orderIndex = document.getOrderIndex(elementId);
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan.single(elementId);
}

DynamicSceneOptimizationPlan? _resolveSerialNumberOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  final document = view.state.domain.document;
  if (!SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
    interaction: interaction,
    document: document,
  )) {
    return null;
  }
  if (interaction is! EditingState) {
    return null;
  }

  final selectedId = interaction.context.selectedIdsAtStart.first;
  if (view.selectedIds.length != 1 || !view.selectedIds.contains(selectedId)) {
    return null;
  }

  final element = document.getElementById(selectedId);
  final preview = view.previewElementsById[selectedId];
  if (element == null ||
      preview == null ||
      element.data is! SerialNumberData ||
      preview.data is! SerialNumberData) {
    return null;
  }

  final serialData = preview.data as SerialNumberData;
  final companionIds = <String>{selectedId};
  final textId = serialData.textElementId;
  if (textId != null) {
    final textElement = document.getElementById(textId);
    if (textElement?.data is TextData) {
      companionIds.add(textId);
    }
  }

  final orderIndex = _resolveLowestOrderIndex(
    document: document,
    elementIds: companionIds,
  );
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan(
    optimizedElementIds: companionIds,
    staticHiddenElementIds: companionIds,
  );
}

DynamicSceneOptimizationPlan? _resolveHighlightEditOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  if (interaction is! EditingState) {
    return null;
  }

  final previewElements = view.previewElementsById;
  if (previewElements.isEmpty ||
      previewElements.length > _maxLocalizedPreviewElementCount) {
    return null;
  }

  final document = view.state.domain.document;
  final candidateIds = <String>{};
  for (final entry in previewElements.entries) {
    final persisted = document.getElementById(entry.key);
    if (persisted == null) {
      continue;
    }
    final previewIsHighlight = entry.value.data is HighlightData;
    final persistedIsHighlight = persisted.data is HighlightData;
    if (!previewIsHighlight || !persistedIsHighlight) {
      return null;
    }
    candidateIds.add(entry.key);
  }
  if (candidateIds.isEmpty) {
    return null;
  }

  final selectedIds = view.selectedIds;
  if (selectedIds.isEmpty) {
    return null;
  }
  for (final selectedId in selectedIds) {
    final selected = document.getElementById(selectedId);
    if (selected == null || selected.data is! HighlightData) {
      return null;
    }
    candidateIds.add(selectedId);
    if (candidateIds.length > _maxLocalizedPreviewElementCount) {
      return null;
    }
  }

  final orderIndex = _resolveLowestOrderIndex(
    document: document,
    elementIds: candidateIds,
  );
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan(
    optimizedElementIds: candidateIds,
    staticHiddenElementIds: candidateIds,
  );
}

DynamicSceneOptimizationPlan? _resolveSingleSelectionEditOptimizationPlan(
  DrawStateView view,
) {
  final interaction = view.state.application.interaction;
  if (interaction is! EditingState || view.selectedIds.length != 1) {
    return null;
  }

  final previewElements = view.previewElementsById;
  if (previewElements.isEmpty ||
      previewElements.length > _maxLocalizedPreviewElementCount) {
    return null;
  }

  final document = view.state.domain.document;
  final candidateIds = <String>{};
  for (final entry in previewElements.entries) {
    final persisted = document.getElementById(entry.key);
    if (persisted == null) {
      continue;
    }
    if (_isBlendSensitiveElement(entry.value)) {
      return null;
    }
    candidateIds.add(entry.key);
  }
  _includeSerialCompanionTextIds(
    document: document,
    previewElementsById: previewElements,
    candidateIds: candidateIds,
  );
  if (candidateIds.isEmpty) {
    return null;
  }

  final orderIndex = _resolveLowestOrderIndex(
    document: document,
    elementIds: candidateIds,
  );
  if (orderIndex == null ||
      !_canApplyLocalizedOptimization(document, orderIndex)) {
    return null;
  }

  return DynamicSceneOptimizationPlan(
    optimizedElementIds: candidateIds,
    staticHiddenElementIds: candidateIds,
  );
}

bool _canApplyLocalizedOptimization(DocumentState document, int orderIndex) =>
    !document.hasBlendSensitiveElementAboveOrderIndex(
      orderIndex,
      includeTransparent: false,
    );

bool _isBlendSensitiveElement(ElementState element) {
  final data = element.data;
  return data is HighlightData || data is FilterData;
}

void _includeSerialCompanionTextIds({
  required DocumentState document,
  required Map<String, ElementState> previewElementsById,
  required Set<String> candidateIds,
}) {
  if (candidateIds.isEmpty) {
    return;
  }

  final companionTextIds = <String>{};
  for (final id in candidateIds) {
    final effectiveCandidate =
        previewElementsById[id] ?? document.getElementById(id);
    final data = effectiveCandidate?.data;
    if (data is! SerialNumberData) {
      continue;
    }

    final textId = data.textElementId;
    if (textId == null || textId.isEmpty) {
      continue;
    }

    final textElement =
        previewElementsById[textId] ?? document.getElementById(textId);
    if (textElement?.data is TextData) {
      companionTextIds.add(textId);
    }
  }

  if (companionTextIds.isNotEmpty) {
    candidateIds.addAll(companionTextIds);
  }
}

int? _resolveLowestOrderIndex({
  required DocumentState document,
  required Set<String> elementIds,
}) {
  var lowestOrderIndex = -1;
  for (final elementId in elementIds) {
    final orderIndex = document.getOrderIndex(elementId);
    if (orderIndex == null) {
      continue;
    }
    if (lowestOrderIndex < 0 || orderIndex < lowestOrderIndex) {
      lowestOrderIndex = orderIndex;
    }
  }
  return lowestOrderIndex < 0 ? null : lowestOrderIndex;
}
