import 'arrow_elbow_core.dart' as elbow_core;
import 'arrow_types.dart';

/// Base routing padding used by the elbow router.
///
/// Mirrors `BASE_PADDING` from the TypeScript port entrypoint.
const double basePadding = elbow_core.basePadding;

/// TypeScript compatibility alias for [basePadding].
// ignore: constant_identifier_names
const double BASE_PADDING = basePadding;

/// Updates or recomputes elbow points from the provided input payload.
///
/// This preserves the exported TypeScript API shape by delegating to the
/// translated elbow core implementation.
ArrowPatch updateElbowArrowPoints(
  Object arrowOrInput, [
  Object? elementsMap,
  Object? updates,
  Map<String, dynamic>? options,
]) {
  if (arrowOrInput is Map<String, dynamic>) {
    return elbow_core.updateElbowArrowPoints(arrowOrInput);
  }

  final arrow = _readArrow(arrowOrInput);
  if (arrow == null) {
    throw StateError('arrow must be an ArrowState');
  }

  final bindablesById = _readBindableMap(elementsMap);
  final bindables = bindablesById.values.toList(growable: false);
  final updatePatch = _readUpdatePatch(updates);
  final context = normalizeEngineContext(<String, dynamic>{
    if (options != null && options['zoom'] is num) 'zoom': options['zoom'],
    if (options != null && options['maxCoordinate'] is num)
      'maxCoordinate': options['maxCoordinate'],
  });

  return elbow_core.updateElbowArrowPatch(<String, dynamic>{
    'arrow': arrow,
    'updates': updatePatch,
    'bindables': bindables,
    'context': context,
    if (options != null)
      'options': <String, dynamic>{
        if (options.containsKey('isDragging'))
          'isDragging': options['isDragging'] == true,
        if (options.containsKey('validateInvariants'))
          'validateInvariants': options['validateInvariants'] == true,
      },
  });
}

/// Validates that all consecutive elbow segments stay orthogonal.
bool validateElbowPoints(List<Point> points, [double tolerance = 1]) =>
    elbow_core.validateElbowPoints(points, tolerance);

ArrowState? _readArrow(Object? value) => value is ArrowState ? value : null;

Map<String, BindableState> _readBindableMap(Object? value) {
  if (value is Map<String, BindableState>) {
    return value;
  }
  if (value is Map) {
    final out = <String, BindableState>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final bindable = entry.value;
      if (key is String && bindable is BindableState) {
        out[key] = bindable;
      }
    }
    return out;
  }
  return <String, BindableState>{};
}

ElbowUpdatePatch _readUpdatePatch(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        out[key] = entry.value;
      }
    }
    return out;
  }
  return <String, dynamic>{};
}
