import '../../../config/draw_config.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/snapping_mode.dart';
import 'arrow_binding.dart';
import 'arrow_binding_target_cache.dart';

const _bindingCacheTargetThresholdFactor = 0.4;
const _bindingCacheEmptyThresholdFactor = 0.75;
const _bindingCacheCandidateThresholdFactor = 0.35;
const _bindingCacheCandidateReferenceThresholdFactor = 0.35;
const _preferredBindingStickinessFactor = 0.3;

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
  }) {
    if (!snapConfig.enableArrowBinding) {
      return false;
    }
    if (snappingMode == SnappingMode.grid) {
      return false;
    }
    if (snapConfig.enabled && snappingMode == SnappingMode.none) {
      return false;
    }
    return true;
  }

  /// Resolves effective binding distance in world units.
  static double resolveBindingDistance({
    required DrawState state,
    required SnapConfig snapConfig,
  }) {
    final zoom = state.application.view.camera.zoom;
    final effectiveZoom = zoom == 0 ? 1.0 : zoom;
    return snapConfig.arrowBindingDistance / effectiveZoom;
  }

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

    final preferredTarget = state.domain.document.getElementById(
      preferredBinding.elementId,
    );
    if (preferredTarget == null ||
        preferredTarget.opacity <= 0 ||
        preferredTarget.id == excludedElementId ||
        !ArrowBindingUtils.isBindableTarget(preferredTarget)) {
      return null;
    }

    final candidate = arrowType == ArrowType.elbow
        ? ArrowBindingUtils.resolveElbowBindingCandidateForTarget(
            worldPoint: worldPoint,
            target: preferredTarget,
            snapDistance: snapDistance,
            hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBindingCandidateForTarget(
            worldPoint: worldPoint,
            target: preferredTarget,
            snapDistance: snapDistance,
            referencePoint: referencePoint,
          );
    if (candidate == null) {
      return null;
    }
    if (!allowNewBinding) {
      return candidate;
    }
    if (candidate.distance <=
        snapDistance * _preferredBindingStickinessFactor) {
      return candidate;
    }
    return null;
  }

  /// Resolves the preferred binding candidate from a target list.
  static ArrowBindingResult? resolvePreferredBindingCandidate({
    required DrawPoint worldPoint,
    required List<ElementState> targets,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required double snapDistance,
    required bool allowNewBinding,
    ArrowBinding? preferredBinding,
    DrawPoint? referencePoint,
  }) {
    if (preferredBinding == null) {
      return null;
    }
    final preferredTarget = _findTargetById(
      targets,
      preferredBinding.elementId,
    );
    if (preferredTarget == null) {
      return null;
    }
    final preferredCandidate = arrowType == ArrowType.elbow
        ? ArrowBindingUtils.resolveElbowBindingCandidateForTarget(
            worldPoint: worldPoint,
            target: preferredTarget,
            snapDistance: snapDistance,
            hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBindingCandidateForTarget(
            worldPoint: worldPoint,
            target: preferredTarget,
            snapDistance: snapDistance,
            referencePoint: referencePoint,
          );
    if (preferredCandidate == null) {
      return null;
    }
    if (!allowNewBinding) {
      return preferredCandidate;
    }
    if (preferredCandidate.distance <=
        snapDistance * _preferredBindingStickinessFactor) {
      return preferredCandidate;
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
    double targetCacheThresholdFactor = _bindingCacheTargetThresholdFactor,
    double emptyCacheThresholdFactor = _bindingCacheEmptyThresholdFactor,
    double candidateCacheThresholdFactor =
        _bindingCacheCandidateThresholdFactor,
    double candidateCacheReferenceThresholdFactor =
        _bindingCacheCandidateReferenceThresholdFactor,
  }) {
    if (snapDistance <= 0 || !shouldLookupBindings) {
      cache?.reset();
      return null;
    }
    if (!allowNewBinding && preferredBinding == null) {
      cache?.reset();
      return null;
    }

    final elementsVersion = state.domain.document.elementsVersion;
    final cachedCandidate = cache?.resolveCandidate(
      position: worldPoint,
      referencePoint: referencePoint,
      positionThreshold: snapDistance * candidateCacheThresholdFactor,
      referenceThreshold: snapDistance * candidateCacheReferenceThresholdFactor,
      elementsVersion: elementsVersion,
      snapDistance: snapDistance,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      shouldLookupBindings: shouldLookupBindings,
      allowNewBinding: allowNewBinding,
      hasBindableTargets: hasBindableTargets,
      preferredBinding: preferredBinding,
      excludedElementId: excludedElementId,
    );
    if (cachedCandidate != null && cachedCandidate.hasValue) {
      return cachedCandidate.value;
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
      _cacheEndpointCandidate(
        cache: cache,
        worldPoint: worldPoint,
        referencePoint: referencePoint,
        elementsVersion: elementsVersion,
        snapDistance: snapDistance,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        hasBindableTargets: hasBindableTargets,
        preferredBinding: preferredBinding,
        excludedElementId: excludedElementId,
        value: preferredDirect,
      );
      return preferredDirect;
    }

    if (!hasBindableTargets) {
      _cacheEndpointCandidate(
        cache: cache,
        worldPoint: worldPoint,
        referencePoint: referencePoint,
        elementsVersion: elementsVersion,
        snapDistance: snapDistance,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        hasBindableTargets: hasBindableTargets,
        preferredBinding: preferredBinding,
        excludedElementId: excludedElementId,
        value: null,
      );
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
      targetCacheThresholdFactor: targetCacheThresholdFactor,
      emptyCacheThresholdFactor: emptyCacheThresholdFactor,
    );
    if (targets.isEmpty) {
      _cacheEndpointCandidate(
        cache: cache,
        worldPoint: worldPoint,
        referencePoint: referencePoint,
        elementsVersion: elementsVersion,
        snapDistance: snapDistance,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        hasBindableTargets: hasBindableTargets,
        preferredBinding: preferredBinding,
        excludedElementId: excludedElementId,
        value: null,
      );
      return null;
    }

    final preferredFromTargets = resolvePreferredBindingCandidate(
      worldPoint: worldPoint,
      targets: targets,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      snapDistance: snapDistance,
      allowNewBinding: allowNewBinding,
      preferredBinding: preferredBinding,
      referencePoint: referencePoint,
    );
    if (preferredFromTargets != null) {
      _cacheEndpointCandidate(
        cache: cache,
        worldPoint: worldPoint,
        referencePoint: referencePoint,
        elementsVersion: elementsVersion,
        snapDistance: snapDistance,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        hasBindableTargets: hasBindableTargets,
        preferredBinding: preferredBinding,
        excludedElementId: excludedElementId,
        value: preferredFromTargets,
      );
      return preferredFromTargets;
    }

    if (arrowType == ArrowType.elbow) {
      final elbowCandidate = ArrowBindingUtils.resolveElbowBindingCandidate(
        worldPoint: worldPoint,
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
      );
      _cacheEndpointCandidate(
        cache: cache,
        worldPoint: worldPoint,
        referencePoint: referencePoint,
        elementsVersion: elementsVersion,
        snapDistance: snapDistance,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        hasBindableTargets: hasBindableTargets,
        preferredBinding: preferredBinding,
        excludedElementId: excludedElementId,
        value: elbowCandidate,
      );
      return elbowCandidate;
    }

    final candidate = ArrowBindingUtils.resolveBindingCandidate(
      worldPoint: worldPoint,
      targets: targets,
      snapDistance: snapDistance,
      preferredBinding: preferredBinding,
      allowNewBinding: allowNewBinding,
      referencePoint: referencePoint,
    );
    _cacheEndpointCandidate(
      cache: cache,
      worldPoint: worldPoint,
      referencePoint: referencePoint,
      elementsVersion: elementsVersion,
      snapDistance: snapDistance,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      shouldLookupBindings: shouldLookupBindings,
      allowNewBinding: allowNewBinding,
      hasBindableTargets: hasBindableTargets,
      preferredBinding: preferredBinding,
      excludedElementId: excludedElementId,
      value: candidate,
    );
    return candidate;
  }

  /// Resolves nearby bindable targets using [cache] when possible.
  static List<ElementState> resolveBindingTargetsCached({
    required DrawState state,
    required DrawPoint position,
    required double distance,
    ArrowBindingTargetCache? cache,
    String? excludedElementId,
    double targetCacheThresholdFactor = _bindingCacheTargetThresholdFactor,
    double emptyCacheThresholdFactor = _bindingCacheEmptyThresholdFactor,
  }) {
    assert(
      targetCacheThresholdFactor >= 0,
      'targetCacheThresholdFactor must be non-negative',
    );
    assert(
      emptyCacheThresholdFactor >= 0,
      'emptyCacheThresholdFactor must be non-negative',
    );
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
        ? emptyCacheThresholdFactor
        : targetCacheThresholdFactor;
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

void _cacheEndpointCandidate({
  required ArrowBindingTargetCache? cache,
  required DrawPoint worldPoint,
  required DrawPoint? referencePoint,
  required int elementsVersion,
  required double snapDistance,
  required ArrowType arrowType,
  required ArrowheadStyle arrowheadStyle,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required bool hasBindableTargets,
  required ArrowBinding? preferredBinding,
  required ArrowBindingResult? value,
  String? excludedElementId,
}) {
  cache?.cacheCandidate(
    position: worldPoint,
    referencePoint: referencePoint,
    elementsVersion: elementsVersion,
    snapDistance: snapDistance,
    arrowType: arrowType,
    arrowheadStyle: arrowheadStyle,
    shouldLookupBindings: shouldLookupBindings,
    allowNewBinding: allowNewBinding,
    hasBindableTargets: hasBindableTargets,
    preferredBinding: preferredBinding,
    excludedElementId: excludedElementId,
    value: value,
  );
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

ElementState? _findTargetById(List<ElementState> targets, String id) {
  for (final target in targets) {
    if (target.id == id) {
      return target;
    }
  }
  return null;
}
