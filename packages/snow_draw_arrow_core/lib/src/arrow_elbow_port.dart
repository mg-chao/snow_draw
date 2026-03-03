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
ArrowPatch updateElbowArrowPoints(UpdateElbowArrowInput input) =>
    elbow_core.updateElbowArrowPoints(input);

/// Validates that all consecutive elbow segments stay orthogonal.
bool validateElbowPoints(List<Point> points, [double tolerance = 1]) =>
    elbow_core.validateElbowPoints(points, tolerance);

/// Repairs invalid unbound elbow arrows restored from persisted state.
///
/// Returns an empty patch when no repair is required.
ArrowPatch repairInvalidUnboundElbowArrowOnRestorePatch(
  RepairInvalidUnboundElbowArrowOnRestoreInput input,
) {
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return const <String, dynamic>{};
  }

  final shouldSkipRepair =
      arrow.startBinding != null ||
      arrow.endBinding != null ||
      !arrow.elbowed ||
      validateElbowPoints(arrow.points) ||
      arrow.points.isEmpty;
  if (shouldSkipRepair) {
    return const <String, dynamic>{};
  }

  final lastPoint = arrow.points.last;
  return elbow_core.updateElbowArrowPatch(<String, dynamic>{
    'arrow': arrow,
    'updates': <String, dynamic>{
      'points': <Point>[
        <double>[0, 0],
        <double>[lastPoint[0], lastPoint[1]],
      ],
    },
    'bindables': _readBindables(input['bindables']),
    'context': _readContext(input['context']),
  });
}

/// Repairs pathological self-bound elbow arrows with extreme coordinates.
///
/// Returns an empty patch when no repair is required.
ArrowPatch repairSelfBoundExtremeElbowArrowOnRestorePatch(
  RepairSelfBoundExtremeElbowArrowOnRestoreInput input,
) {
  final maxCoordinate =
      _readFiniteDouble(input['maxCoordinate']) ??
      defaultEngineContext.maxCoordinate;
  final arrow = _readArrow(input['arrow']);
  final bindable = _readBindable(input['bindable']);
  if (arrow == null || bindable == null) {
    return const <String, dynamic>{};
  }

  final isSelfBound =
      arrow.startBinding != null &&
      arrow.endBinding != null &&
      arrow.startBinding!.elementId == arrow.endBinding!.elementId &&
      arrow.startBinding!.elementId == bindable.id;
  final shouldSkipRepair =
      !arrow.elbowed || !isSelfBound || arrow.points.length <= 1;
  if (shouldSkipRepair) {
    return const <String, dynamic>{};
  }

  final hasExtremePoint = arrow.points.any(
    (point) => point[0].abs() > maxCoordinate || point[1].abs() > maxCoordinate,
  );
  if (!hasExtremePoint) {
    return const <String, dynamic>{};
  }

  // Mirrors upstream restore fallback geometry for self-bound extreme elbows.
  return <String, dynamic>{
    'x': bindable.x + bindable.width / 2,
    'y': bindable.y - 5,
    'width': bindable.width,
    'height': bindable.height,
    'points': <Point>[
      <double>[0, 0],
      <double>[0, -10],
      <double>[bindable.width / 2 + 5, -10],
      <double>[bindable.width / 2 + 5, bindable.height / 2 + 5],
    ],
  };
}

ArrowState? _readArrow(Object? value) => value is ArrowState ? value : null;

BindableState? _readBindable(Object? value) =>
    value is BindableState ? value : null;

List<BindableState> _readBindables(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableState>().toList(growable: false);
  }
  return const <BindableState>[];
}

EngineContext _readContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  if (value is Map<String, dynamic>) {
    return normalizeEngineContext(value);
  }
  if (value is Map) {
    final normalized = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        normalized[key] = entry.value;
      }
    }
    return normalizeEngineContext(normalized);
  }
  return defaultEngineContext;
}

double? _readFiniteDouble(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
