/// Returns a safe zoom factor for distance conversions.
///
/// Non-finite or non-positive values fall back to `1.0` so callers can
/// keep distance math stable even when camera data is temporarily invalid.
double resolveEffectiveZoom(double zoom) =>
    zoom.isFinite && zoom > 0 ? zoom : 1.0;

/// Converts a screen-space distance to world-space distance using [zoom].
double resolveZoomAdjustedDistance({
  required double distance,
  required double zoom,
}) => distance / resolveEffectiveZoom(zoom);
