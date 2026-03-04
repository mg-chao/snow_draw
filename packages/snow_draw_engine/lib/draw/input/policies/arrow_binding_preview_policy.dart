import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../utils/snapping_mode.dart';

/// Returns whether arrow binding preview should be evaluated.
bool shouldPreviewArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
}) =>
    snapConfig.enableArrowBinding &&
    snappingMode != SnappingMode.grid &&
    !(snapConfig.enabled && snappingMode == SnappingMode.none);

/// Resolves bindable targets near [position].
List<ElementState> resolveArrowBindingTargets({
  required DrawState state,
  required DrawPoint position,
  required double distance,
}) {
  final document = state.domain.document;
  final targets = <ElementState>[];
  document.visitArrowBindableElementsAtPoint(position, distance, (element) {
    if (element.opacity > 0) {
      targets.add(element);
    }
    return true;
  });
  return targets;
}
