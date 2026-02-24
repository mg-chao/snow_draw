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
