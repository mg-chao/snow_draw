import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../utils/combined_element_lookup.dart';
import '../arrow_binding.dart';
import '../arrow_core_bridge.dart';
import '../arrow_core_ops.dart';
import '../arrow_data.dart';
import 'elbow_fixed_segment.dart';

const _bindingOverrideUnset = Object();

@immutable
final class ElbowEditResult {
  const ElbowEditResult({
    required this.localPoints,
    required this.fixedSegments,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> localPoints;
  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;
}

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required CombinedElementLookup lookup,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  Object? startBindingOverride = _bindingOverrideUnset,
  Object? endBindingOverride = _bindingOverrideUnset,
  core.EngineContext? engineContext,
  bool finalize = false,
}) {
  final startBinding = _resolveBindingOverride(
    override: startBindingOverride,
    current: data.startBinding,
  );
  final endBinding = _resolveBindingOverride(
    override: endBindingOverride,
    current: data.endBinding,
  );

  final arrowState = toCoreArrowState(
    element: element,
    data: data,
    localPointsOverride: localPointsOverride,
    fixedSegmentsOverride: fixedSegmentsOverride,
    startBindingOverride: startBinding,
    endBindingOverride: endBinding,
  );
  final bindables = collectCoreBindables(lookup.values);

  final hasExplicitUpdates =
      localPointsOverride != null ||
      fixedSegmentsOverride != null ||
      startBindingOverride != _bindingOverrideUnset ||
      endBindingOverride != _bindingOverrideUnset;
  final context = engineContext ?? core.defaultEngineContext;

  final patch = hasExplicitUpdates
      ? updateCoreElbowArrowPatch(
          arrow: arrowState,
          updates: <String, dynamic>{
            if (localPointsOverride != null) 'points': arrowState.points,
            if (fixedSegmentsOverride != null)
              'fixedSegments': arrowState.fixedSegments,
            if (startBindingOverride != _bindingOverrideUnset)
              'startBinding': arrowState.startBinding,
            if (endBindingOverride != _bindingOverrideUnset)
              'endBinding': arrowState.endBinding,
          },
          bindables: bindables,
          context: context,
          options: <String, dynamic>{'isDragging': !finalize},
        )
      : recomputeCoreElbowPatch(
          arrow: arrowState,
          bindables: bindables,
          context: context,
        );

  final nextArrow = core.applyArrowPatch(arrowState, patch);
  final worldPoints = coreArrowWorldPoints(nextArrow);
  final localPoints = worldToLocalPoints(element, worldPoints);
  final fixedSegments = toLocalFixedSegmentsFromCoreArrow(nextArrow, element);

  return ElbowEditResult(
    localPoints: List<DrawPoint>.unmodifiable(localPoints),
    fixedSegments: fixedSegments == null
        ? null
        : List<ElbowFixedSegment>.unmodifiable(fixedSegments),
    startIsSpecial: nextArrow.startIsSpecial,
    endIsSpecial: nextArrow.endIsSpecial,
  );
}

List<ElbowFixedSegment>? transformFixedSegments({
  required List<ElbowFixedSegment>? segments,
  required DrawRect oldRect,
  required DrawRect newRect,
  required double rotation,
}) {
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final newSpace = ElementSpace(rotation: rotation, origin: newRect.center);
  final transformed = segments
      .map((segment) {
        final worldStart = oldSpace.toWorld(segment.start);
        final worldEnd = oldSpace.toWorld(segment.end);
        return segment.copyWith(
          start: newSpace.fromWorld(worldStart),
          end: newSpace.fromWorld(worldEnd),
        );
      })
      .toList(growable: false);
  return transformed.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(transformed);
}

ArrowBinding? _resolveBindingOverride({
  required Object? override,
  required ArrowBinding? current,
}) {
  if (override == _bindingOverrideUnset) {
    return current;
  }
  return override as ArrowBinding?;
}
