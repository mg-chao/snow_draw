import '../../../config/draw_config.dart';
import '../../../utils/snapping_mode.dart';

/// Returns whether arrow binding interactions should run for this pointer mode.
///
/// Excalidraw parity:
/// - binding depends only on the explicit arrow-binding toggle
/// - pointer snap override (Ctrl/Cmd) temporarily disables binding
bool shouldAttemptArrowBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
  bool snapOverrideActive = false,
}) {
  // Keep signature stable for existing callsites; snapping mode does not gate
  // arrow binding behavior.
  final _ = snappingMode;
  if (snapOverrideActive) {
    return false;
  }
  if (!snapConfig.enableArrowBinding) {
    return false;
  }
  return true;
}
