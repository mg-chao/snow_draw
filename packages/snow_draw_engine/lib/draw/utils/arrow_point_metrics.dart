import '../config/draw_config.dart';

const _arrowPointLoopThresholdFactor = 1.5;

/// Resolves the loop-closing threshold for arrow-point interactions.
double resolveConnectorPointLoopThreshold(double hitRadius) {
  if (!hitRadius.isFinite || hitRadius <= 0) {
    return 0;
  }
  return hitRadius * _arrowPointLoopThresholdFactor;
}

/// Resolves rendered arrow-point handle size from control-point size.
double resolveConnectorPointHandleSize(double controlPointSize) {
  if (!controlPointSize.isFinite || controlPointSize <= 0) {
    return 0;
  }
  return controlPointSize * ConfigDefaults.arrowPointSizeMultiplier;
}
