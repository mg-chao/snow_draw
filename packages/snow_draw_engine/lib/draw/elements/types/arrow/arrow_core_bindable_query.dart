import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import 'arrow_binding.dart';
import 'arrow_core_bindable_candidates.dart';
import 'arrow_core_bindable_projector.dart';

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
    document.visitArrowBindableElementsAtPoint(worldPoint, distance, (element) {
      candidateIds.add(element.id);
      return true;
    }, excludedElementId: excludedElementId);
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
  ArrowBinding? activeBinding,
  ArrowBinding? oppositeBinding,
  String? excludedElementId,
  required bool allowNewBinding,
}) {
  if (allowNewBinding) {
    final allBindableElements = <ElementState>[];
    for (final elementId in document.orderedElementIds) {
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
    return projectArrowCoreBindableCandidates(
      elements: allBindableElements,
      bindablesById: document.arrowCoreBindableById,
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
  for (final elementId in document.orderedElementIds) {
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

  return projectArrowCoreBindableCandidates(
    elements: boundElements,
    bindablesById: document.arrowCoreBindableById,
  );
}
