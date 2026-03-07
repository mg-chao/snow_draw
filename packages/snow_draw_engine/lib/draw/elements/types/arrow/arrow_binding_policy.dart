import '../../../config/draw_config.dart';

/// Returns whether arrow binding interactions should run for this pointer mode.
bool shouldAttemptArrowBinding({
  required SnapConfig snapConfig,
  bool snapOverrideActive = false,
}) => !snapOverrideActive && snapConfig.enableArrowBinding;
