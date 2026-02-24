/// Returns `null` for blank input, otherwise returns a trimmed string.
String? normalizeOptionalTrimmedString(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
