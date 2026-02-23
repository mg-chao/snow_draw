import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../utils/snapping_mode.dart';

/// Returns whether arrow binding preview should be evaluated.
bool shouldPreviewArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
}) {
  if (!snapConfig.enableArrowBinding) {
    return false;
  }
  if (snappingMode == SnappingMode.grid) {
    return false;
  }
  if (snapConfig.enabled && snappingMode == SnappingMode.none) {
    return false;
  }
  return true;
}

/// Resolves bindable targets near [position].
List<ElementState> resolveArrowBindingTargets({
  required DrawState state,
  required DrawPoint position,
  required double distance,
}) {
  final document = state.domain.document;
  final targets = <ElementState>[];
  document.visitElementsAtPointTopDown(position, distance, (element) {
    if (element.opacity <= 0 || !ArrowBindingUtils.isBindableTarget(element)) {
      return true;
    }
    targets.add(element);
    return true;
  });
  return targets;
}
