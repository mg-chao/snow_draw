import '../config/draw_config.dart';

enum SnappingMode { none, object, grid }

SnappingMode resolvePersistentSnappingMode({
  required bool gridEnabled,
  required bool objectEnabled,
}) {
  if (gridEnabled) {
    return SnappingMode.grid;
  }
  if (objectEnabled) {
    return SnappingMode.object;
  }
  return SnappingMode.none;
}

SnappingMode resolveEffectiveSnappingMode({
  required bool gridEnabled,
  required bool objectEnabled,
  required bool ctrlPressed,
}) {
  final persistent = resolvePersistentSnappingMode(
    gridEnabled: gridEnabled,
    objectEnabled: objectEnabled,
  );
  if (!ctrlPressed) {
    return persistent;
  }
  return persistent == SnappingMode.none
      ? SnappingMode.object
      : SnappingMode.none;
}

SnappingMode resolveEffectiveSnappingModeForConfig({
  required DrawConfig config,
  required bool ctrlPressed,
}) => resolveEffectiveSnappingMode(
  gridEnabled: config.grid.enabled,
  objectEnabled: config.snap.enabled,
  ctrlPressed: ctrlPressed,
);
