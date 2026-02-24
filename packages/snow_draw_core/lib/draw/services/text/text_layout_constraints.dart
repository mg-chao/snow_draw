/// Ensures text max-width constraints are finite and positive.
double resolveTextMaxWidth(double maxWidth) {
  if (!maxWidth.isFinite) {
    return double.infinity;
  }
  if (maxWidth <= 0) {
    return 1;
  }
  return maxWidth;
}

/// Returns [value] when it is finite and positive, otherwise [fallback].
double sanitizePositiveExtent(double value, {required double fallback}) {
  if (value.isFinite && value > 0) {
    return value;
  }
  return fallback;
}
