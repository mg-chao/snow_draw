import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import 'arrow_binding.dart';
import 'arrow_core_bindable_candidates.dart';

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

  final bindableById = document.arrowCoreBindableById;
  final elements = <ElementState>[];
  final bindables = <core.BindableState>[];
  for (final candidateId in document.orderedElementIds) {
    if (!candidateIds.contains(candidateId)) {
      continue;
    }
    final element = document.elementMap[candidateId];
    if (element == null || element.opacity <= 0) {
      continue;
    }

    final bindable = bindableById[candidateId];
    if (bindable == null) {
      continue;
    }
    elements.add(element);
    bindables.add(bindable);
  }

  if (bindables.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }

  return ArrowCoreBindableCandidates(
    elements: List<ElementState>.unmodifiable(elements),
    bindables: List<core.BindableState>.unmodifiable(bindables),
  );
}
