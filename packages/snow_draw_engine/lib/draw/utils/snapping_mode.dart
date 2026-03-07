import '../config/draw_config.dart';

enum SnappingMode { none, object, grid }

SnappingMode resolvePersistentSnappingMode({
  required bool gridEnabled,
  required bool objectEnabled,
}) => gridEnabled
    ? SnappingMode.grid
    : objectEnabled
    ? SnappingMode.object
    : SnappingMode.none;

SnappingMode resolveEffectiveSnappingMode({
  required bool gridEnabled,
  required bool objectEnabled,
  required bool ctrlPressed,
}) {
  if (ctrlPressed) {
    return gridEnabled || objectEnabled
        ? SnappingMode.none
        : SnappingMode.object;
  }
  return resolvePersistentSnappingMode(
    gridEnabled: gridEnabled,
    objectEnabled: objectEnabled,
  );
}

SnappingMode resolveEffectiveSnappingModeForConfig({
  required DrawConfig config,
  required bool ctrlPressed,
}) => resolveEffectiveSnappingMode(
  gridEnabled: config.grid.enabled,
  objectEnabled: config.snap.enabled,
  ctrlPressed: ctrlPressed,
);
