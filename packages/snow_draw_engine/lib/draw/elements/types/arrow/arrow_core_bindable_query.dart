import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import 'arrow_binding.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bindable_candidates.dart';
import 'arrow_core_bindable_projector.dart';
import 'arrow_core_bridge.dart';

/// Resolves bindable lookup candidates for arrow-core binding/focus routines.
///
/// The result always includes currently bound endpoint targets (when provided)
/// and optionally includes nearby spatial candidates around [worldPoint].
ArrowCoreBindableCandidates resolveCoreBindableCandidates({
  required DocumentState document,
  required DrawPoint worldPoint,
  required double distance,
  ArrowBinding? preferredBinding,
  ArrowBinding? oppositeBinding,
  String? excludedElementId,
  bool includeNearby = true,
}) {
  final candidateIds = <String>{};
  if (preferredBinding != null) {
    candidateIds.add(preferredBinding.elementId);
  }
  if (oppositeBinding != null) {
    candidateIds.add(oppositeBinding.elementId);
  }

  if (includeNearby && distance > 0 && document.hasArrowBindableElements) {
    final hoveredBindables = core.listHoveredBindables(
      <double>[worldPoint.x, worldPoint.y],
      document.arrowCoreBindables,
      distance,
      stopAtOpaque: true,
    );
    for (final bindable in hoveredBindables) {
      if (excludedElementId != null && bindable.id == excludedElementId) {
        continue;
      }
      candidateIds.add(bindable.id);
    }
  }

  if (candidateIds.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }

  final candidateElements = <ElementState>[];
  for (final candidateId in document.orderedElementIds) {
    if (!candidateIds.contains(candidateId)) {
      continue;
    }
    final element = document.elementMap[candidateId];
    if (element == null) {
      continue;
    }
    candidateElements.add(element);
  }
  return projectArrowCoreBindableCandidates(
    elements: candidateElements,
    bindablesById: document.arrowCoreBindableById,
  );
}

/// Resolves bindables for endpoint strategy/drag routines.
///
/// Excalidraw parity:
/// - allow new binding -> provide all bindables in document z-order
/// - disallow new binding -> keep only currently bound endpoint targets
ArrowCoreBindableCandidates resolveCoreBindableCandidatesForEndpointStrategy({
  required DocumentState document,
  required bool allowNewBinding,
  ArrowBinding? activeBinding,
  ArrowBinding? oppositeBinding,
  String? excludedElementId,
  List<String>? orderedElementIds,
}) {
  final hasOrderOverride =
      orderedElementIds != null && orderedElementIds.isNotEmpty;
  final orderedIds = hasOrderOverride
      ? orderedElementIds
      : document.orderedElementIds;
  final canReuseCachedBindableProjection =
      !hasOrderOverride ||
      _stringListEquals(orderedIds, document.orderedElementIds);

  if (allowNewBinding) {
    final allBindableElements = <ElementState>[];
    for (final elementId in orderedIds) {
      if (excludedElementId != null && elementId == excludedElementId) {
        continue;
      }
      if (!document.arrowCoreBindableById.containsKey(elementId)) {
        continue;
      }
      final element = document.elementMap[elementId];
      if (element == null) {
        continue;
      }
      allBindableElements.add(element);
    }

    if (allBindableElements.isEmpty) {
      return ArrowCoreBindableCandidates.empty;
    }

    if (canReuseCachedBindableProjection) {
      return projectArrowCoreBindableCandidates(
        elements: allBindableElements,
        bindablesById: document.arrowCoreBindableById,
      );
    }

    final bindablesById = <String, core.BindableState>{};
    for (var index = 0; index < orderedIds.length; index += 1) {
      final elementId = orderedIds[index];
      if (excludedElementId != null && elementId == excludedElementId) {
        continue;
      }
      if (!document.arrowCoreBindableById.containsKey(elementId)) {
        continue;
      }
      final element = document.elementMap[elementId];
      if (element == null) {
        continue;
      }
      final bindable = toCoreBindableState(element, zIndex: index);
      if (bindable == null) {
        continue;
      }
      bindablesById[element.id] = bindable;
    }
    return projectArrowCoreBindableCandidates(
      elements: allBindableElements,
      bindablesById: bindablesById,
    );
  }

  final boundIds = <String>{};
  final activeId = activeBinding?.elementId;
  if (activeId != null && activeId.isNotEmpty) {
    boundIds.add(activeId);
  }
  final oppositeId = oppositeBinding?.elementId;
  if (oppositeId != null && oppositeId.isNotEmpty) {
    boundIds.add(oppositeId);
  }
  if (boundIds.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }

  final boundElements = <ElementState>[];
  for (final elementId in orderedIds) {
    if (!boundIds.contains(elementId)) {
      continue;
    }
    if (excludedElementId != null && elementId == excludedElementId) {
      continue;
    }
    final element = document.elementMap[elementId];
    if (element == null) {
      continue;
    }
    boundElements.add(element);
  }

  if (boundElements.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }

  if (canReuseCachedBindableProjection) {
    return projectArrowCoreBindableCandidates(
      elements: boundElements,
      bindablesById: document.arrowCoreBindableById,
    );
  }

  final bindablesById = <String, core.BindableState>{};
  for (var index = 0; index < orderedIds.length; index += 1) {
    final elementId = orderedIds[index];
    if (!boundIds.contains(elementId)) {
      continue;
    }
    if (excludedElementId != null && elementId == excludedElementId) {
      continue;
    }
    final element = document.elementMap[elementId];
    if (element == null) {
      continue;
    }
    final bindable = toCoreBindableState(element, zIndex: index);
    if (bindable == null) {
      continue;
    }
    bindablesById[element.id] = bindable;
  }

  return projectArrowCoreBindableCandidates(
    elements: boundElements,
    bindablesById: bindablesById,
  );
}

bool _stringListEquals(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
