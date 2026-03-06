import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_binding_policy.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../utils/snapping_mode.dart';

/// Returns whether arrow binding preview should be evaluated.
bool shouldPreviewArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
  bool snapOverrideActive = false,
}) => shouldAttemptArrowBinding(
  snapConfig: snapConfig,
  snappingMode: snappingMode,
  snapOverrideActive: snapOverrideActive,
);

/// Resolves bindable targets near [position].
List<ElementState> resolveArrowBindingTargets({
  required DrawState state,
  required DrawPoint position,
  required double distance,
}) {
  if (distance <= 0) {
    return const <ElementState>[];
  }

  final document = state.domain.document;
  if (!document.hasArrowBindableElements) {
    return const <ElementState>[];
  }

  final hovered = core.listHoveredBindables(
    <double>[position.x, position.y],
    document.arrowCoreBindables,
    distance,
    stopAtOpaque: true,
  );
  if (hovered.isEmpty) {
    return const <ElementState>[];
  }

  final orderedTargets = <ElementState>[];
  for (final bindable in hovered) {
    final element = document.elementMap[bindable.id];
    if (element != null && element.opacity > 0) {
      orderedTargets.add(element);
    }
  }
  if (orderedTargets.isEmpty) {
    return const <ElementState>[];
  }
  return List<ElementState>.unmodifiable(orderedTargets);
}
