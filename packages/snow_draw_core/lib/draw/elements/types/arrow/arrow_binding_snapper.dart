import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/camera_zoom.dart';
import '../../../utils/snapping_mode.dart';
import 'arrow_binding.dart';
import 'arrow_binding_target_cache.dart';

const _preferredBindingStickinessFactor = 0.3;

@immutable
class ArrowBindingCachePolicy {
  const ArrowBindingCachePolicy({
    this.targetCacheThresholdFactor = 0.4,
    this.emptyCacheThresholdFactor = 0.75,
  }) : assert(
         targetCacheThresholdFactor >= 0,
         'targetCacheThresholdFactor must be non-negative',
       ),
       assert(
         emptyCacheThresholdFactor >= 0,
         'emptyCacheThresholdFactor must be non-negative',
       );

  static const defaultPolicy = ArrowBindingCachePolicy();

  final double targetCacheThresholdFactor;
  final double emptyCacheThresholdFactor;
}

/// Shared arrow-binding helpers used by create and edit interactions.
///
/// This centralizes the binding lookup policy and caching behavior so
/// arrow creation/edit paths stay consistent and can share optimizations.
class ArrowBindingSnapper {
  const ArrowBindingSnapper._();

  /// Returns whether binding lookup should run for this snapping mode.
  static bool shouldAttemptBinding({
    required SnapConfig snapConfig,
    required SnappingMode snappingMode,
  }) =>
      snapConfig.enableArrowBinding &&
      snappingMode != SnappingMode.grid &&
      !(snapConfig.enabled && snappingMode == SnappingMode.none);

  /// Resolves effective binding distance in world units.
  static double resolveBindingDistance({
    required DrawState state,
    required SnapConfig snapConfig,
  }) => resolveZoomAdjustedDistance(
    distance: snapConfig.arrowBindingDistance,
    zoom: state.application.view.camera.zoom,
  );

  /// Attempts to snap to the currently preferred binding target directly.
  ///
  /// This fast path avoids a spatial query while the pointer remains close
  /// to the already-bound target.
  static ArrowBindingResult? resolvePreferredBindingCandidateDirect({
    required DrawState state,
    required DrawPoint worldPoint,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required double snapDistance,
    required bool allowNewBinding,
    ArrowBinding? preferredBinding,
    DrawPoint? referencePoint,
    String? excludedElementId,
  }) {
    if (preferredBinding == null) {
      return null;
    }

    final target = state.domain.document.getElementById(
      preferredBinding.elementId,
    );
    if (target == null ||
        target.opacity <= 0 ||
        target.id == excludedElementId ||
        !ArrowBindingUtils.isBindableTarget(target)) {
      return null;
    }

    final candidate = _resolveBindingCandidateForTarget(
      target: target,
      worldPoint: worldPoint,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      snapDistance: snapDistance,
      referencePoint: referencePoint,
    );
    if (candidate == null) {
      return null;
    }
    if (!allowNewBinding ||
        candidate.distance <=
            snapDistance * _preferredBindingStickinessFactor) {
      return candidate;
    }
    return null;
  }

  /// Resolves an endpoint binding candidate with shared lookup/caching policy.
  ///
  /// This method combines:
  /// - preferred-binding direct checks (no spatial query),
  /// - cached nearby-target lookup, and
  /// - fallback best-candidate resolution.
  ///
  /// Returns `null` when no valid binding candidate exists.
  static ArrowBindingResult? resolveEndpointBindingCandidate({
    required DrawState state,
    required DrawPoint worldPoint,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required bool shouldLookupBindings,
    required double snapDistance,
    required bool allowNewBinding,
    required bool hasBindableTargets,
    ArrowBinding? preferredBinding,
    DrawPoint? referencePoint,
    ArrowBindingTargetCache? cache,
    String? excludedElementId,
    ArrowBindingCachePolicy cachePolicy = ArrowBindingCachePolicy.defaultPolicy,
  }) {
    if (!_canResolveEndpointBindingLookup(
      snapDistance: snapDistance,
      shouldLookupBindings: shouldLookupBindings,
      allowNewBinding: allowNewBinding,
      preferredBinding: preferredBinding,
    )) {
      cache?.reset();
      return null;
    }

    final preferredDirect = resolvePreferredBindingCandidateDirect(
      state: state,
      worldPoint: worldPoint,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      snapDistance: snapDistance,
      allowNewBinding: allowNewBinding,
      preferredBinding: preferredBinding,
      referencePoint: referencePoint,
      excludedElementId: excludedElementId,
    );
    if (preferredDirect != null) {
      return preferredDirect;
    }

    if (!allowNewBinding || !hasBindableTargets) {
      return null;
    }

    final searchDistance = ArrowBindingUtils.resolveBindingSearchDistance(
      snapDistance,
    );
    final targets = resolveBindingTargetsCached(
      state: state,
      position: worldPoint,
      distance: searchDistance,
      cache: cache,
      excludedElementId: excludedElementId,
      cachePolicy: cachePolicy,
    );
    if (targets.isEmpty) {
      return null;
    }

    if (arrowType == ArrowType.elbow) {
      return ArrowBindingUtils.resolveElbowBindingCandidate(
        worldPoint: worldPoint,
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
      );
    }

    return ArrowBindingUtils.resolveBindingCandidate(
      worldPoint: worldPoint,
      targets: targets,
      snapDistance: snapDistance,
      preferredBinding: preferredBinding,
      allowNewBinding: allowNewBinding,
      referencePoint: referencePoint,
    );
  }

  /// Resolves nearby bindable targets using [cache] when possible.
  static List<ElementState> resolveBindingTargetsCached({
    required DrawState state,
    required DrawPoint position,
    required double distance,
    ArrowBindingTargetCache? cache,
    String? excludedElementId,
    ArrowBindingCachePolicy cachePolicy = ArrowBindingCachePolicy.defaultPolicy,
  }) {
    if (cache == null) {
      return _resolveBindingTargets(
        state: state,
        position: position,
        distance: distance,
        excludedElementId: excludedElementId,
      );
    }
    final elementsVersion = state.domain.document.elementsVersion;
    final thresholdFactor = cache.targets.isEmpty
        ? cachePolicy.emptyCacheThresholdFactor
        : cachePolicy.targetCacheThresholdFactor;
    final threshold = distance * thresholdFactor;
    if (cache.isValid(
      position: position,
      threshold: threshold,
      distance: distance,
      elementsVersion: elementsVersion,
    )) {
      return cache.targets;
    }

    final targets = _resolveBindingTargets(
      state: state,
      position: position,
      distance: distance,
      excludedElementId: excludedElementId,
    );
    cache.update(
      position: position,
      distance: distance,
      elementsVersion: elementsVersion,
      targets: targets,
    );
    return targets;
  }
}

List<ElementState> _resolveBindingTargets({
  required DrawState state,
  required DrawPoint position,
  required double distance,
  String? excludedElementId,
}) {
  final document = state.domain.document;
  final targets = <ElementState>[];
  document.visitArrowBindableElementsAtPoint(position, distance, (element) {
    targets.add(element);
    return true;
  }, excludedElementId: excludedElementId);
  return targets;
}

ArrowBindingResult? _resolveBindingCandidateForTarget({
  required ElementState target,
  required DrawPoint worldPoint,
  required ArrowType arrowType,
  required ArrowheadStyle arrowheadStyle,
  required double snapDistance,
  DrawPoint? referencePoint,
}) => arrowType == ArrowType.elbow
    ? ArrowBindingUtils.resolveElbowBindingCandidateForTarget(
        worldPoint: worldPoint,
        target: target,
        snapDistance: snapDistance,
        hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
      )
    : ArrowBindingUtils.resolveBindingCandidateForTarget(
        worldPoint: worldPoint,
        target: target,
        snapDistance: snapDistance,
        referencePoint: referencePoint,
      );

bool _canResolveEndpointBindingLookup({
  required double snapDistance,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required ArrowBinding? preferredBinding,
}) =>
    snapDistance > 0 &&
    shouldLookupBindings &&
    (allowNewBinding || preferredBinding != null);
