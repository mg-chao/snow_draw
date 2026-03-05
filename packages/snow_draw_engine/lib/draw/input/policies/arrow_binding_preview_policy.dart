import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_binding_policy.dart';
import '../../elements/types/arrow/arrow_core_bindable_query.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../utils/snapping_mode.dart';

/// Returns whether arrow binding preview should be evaluated.
bool shouldPreviewArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
}) => shouldAttemptArrowBinding(
  snapConfig: snapConfig,
  snappingMode: snappingMode,
);

/// Resolves bindable targets near [position].
List<ElementState> resolveArrowBindingTargets({
  required DrawState state,
  required DrawPoint position,
  required double distance,
}) {
  final candidates = resolveCoreBindableCandidates(
    document: state.domain.document,
    worldPoint: position,
    distance: distance,
  );
  if (candidates.isEmpty) {
    return const <ElementState>[];
  }

  final bindablesById = <String, core.BindableState>{
    for (final bindable in candidates.bindables) bindable.id: bindable,
  };
  final elementsById = <String, ElementState>{
    for (final element in candidates.elements) element.id: element,
  };
  final overlapping = core.pickOverlappingBindables(
    <double>[position.x, position.y],
    candidates.bindables,
    distance,
  );
  if (overlapping.isEmpty) {
    return const <ElementState>[];
  }

  final orderedTargets = <ElementState>[];
  for (final bindable in overlapping) {
    final normalized = bindablesById[bindable.id];
    if (normalized == null) {
      continue;
    }
    final element = elementsById[normalized.id];
    if (element != null && element.opacity > 0) {
      orderedTargets.add(element);
    }
  }
  if (orderedTargets.isEmpty) {
    return const <ElementState>[];
  }
  return List<ElementState>.unmodifiable(orderedTargets);
}
