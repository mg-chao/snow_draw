import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../utils/combined_element_lookup.dart';
import '../arrow_binding.dart';
import '../arrow_core.dart' as core;
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
    required this.startBinding,
    required this.endBinding,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> localPoints;
  final List<ElbowFixedSegment>? fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
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
  final baseData = data.copyWith(
    startBinding: startBinding,
    endBinding: endBinding,
  );

  final baseArrowState = toCoreArrowState(element: element, data: baseData);
  final bindables = collectCoreBindables(lookup.values);

  final hasExplicitUpdates =
      localPointsOverride != null ||
      fixedSegmentsOverride != null ||
      startBindingOverride != _bindingOverrideUnset ||
      endBindingOverride != _bindingOverrideUnset;
  final context = engineContext ?? core.defaultEngineContext;

  final patch = hasExplicitUpdates
      ? updateCoreElbowArrowPatch(
          arrow: baseArrowState,
          updates: <String, dynamic>{
            if (localPointsOverride != null)
              'points': _toCorePointsUpdate(
                element: element,
                localPoints: localPointsOverride,
                baseArrow: baseArrowState,
              ),
            if (fixedSegmentsOverride != null)
              'fixedSegments': _toCoreFixedSegmentsUpdate(
                element: element,
                fixedSegments: fixedSegmentsOverride,
                baseArrow: baseArrowState,
              ),
            if (startBindingOverride != _bindingOverrideUnset)
              'startBinding': toCoreBinding(startBinding),
            if (endBindingOverride != _bindingOverrideUnset)
              'endBinding': toCoreBinding(endBinding),
          },
          bindables: bindables,
          context: context,
          options: <String, dynamic>{'isDragging': !finalize},
        )
      : recomputeCoreElbowPatch(
          arrow: baseArrowState,
          bindables: bindables,
          context: context,
        );

  final nextArrow = core.applyArrowPatch(baseArrowState, patch);
  final worldPoints = coreArrowWorldPoints(nextArrow);
  final localPoints = worldToLocalPoints(element, worldPoints);
  final fixedSegments = toLocalFixedSegmentsFromCoreArrow(nextArrow, element);

  return ElbowEditResult(
    localPoints: List<DrawPoint>.unmodifiable(localPoints),
    fixedSegments: fixedSegments == null
        ? null
        : List<ElbowFixedSegment>.unmodifiable(fixedSegments),
    startBinding: fromCoreBinding(nextArrow.startBinding),
    endBinding: fromCoreBinding(nextArrow.endBinding),
    startIsSpecial: nextArrow.startIsSpecial,
    endIsSpecial: nextArrow.endIsSpecial,
  );
}

List<core.Point> _toCorePointsUpdate({
  required ElementState element,
  required List<DrawPoint> localPoints,
  required core.ArrowState baseArrow,
}) {
  final worldPoints = localToWorldPoints(element, localPoints);
  return worldPoints
      .map((point) => <double>[point.x - baseArrow.x, point.y - baseArrow.y])
      .toList(growable: false);
}

List<core.FixedSegment> _toCoreFixedSegmentsUpdate({
  required ElementState element,
  required List<ElbowFixedSegment> fixedSegments,
  required core.ArrowState baseArrow,
}) {
  if (fixedSegments.isEmpty) {
    return const <core.FixedSegment>[];
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  return fixedSegments
      .map((segment) {
        final worldStart = space.toWorld(segment.start);
        final worldEnd = space.toWorld(segment.end);
        return core.FixedSegment(
          index: segment.index,
          start: <double>[
            worldStart.x - baseArrow.x,
            worldStart.y - baseArrow.y,
          ],
          end: <double>[worldEnd.x - baseArrow.x, worldEnd.y - baseArrow.y],
        );
      })
      .toList(growable: false);
}

List<ElbowFixedSegment>? transformFixedSegments({
  required List<ElbowFixedSegment>? segments,
  required DrawRect oldRect,
  required DrawRect newRect,
  required double rotation,
}) => transformArrowLocalFixedSegments(
  segments: segments,
  oldRect: oldRect,
  newRect: newRect,
  rotation: rotation,
);

ArrowBinding? _resolveBindingOverride({
  required Object? override,
  required ArrowBinding? current,
}) {
  if (override == _bindingOverrideUnset) {
    return current;
  }
  return override as ArrowBinding?;
}
