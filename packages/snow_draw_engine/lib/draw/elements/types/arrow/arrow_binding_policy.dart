import '../../../config/draw_config.dart';
import '../../../utils/snapping_mode.dart';

/// Returns whether arrow binding interactions should run for this pointer mode.
///
/// Binding is disabled when grid snapping is active, when bindings are turned
/// off in config, or when snapping is globally enabled but the current snapping
/// mode is explicitly `none`.
bool shouldAttemptArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
  bool snapOverrideActive = false,
}) {
  if (snapOverrideActive) {
    return false;
  }
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
