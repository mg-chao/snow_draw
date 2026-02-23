import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_binding.dart';

/// Reusable cache for nearby arrow-binding target queries.
///
/// Stores the last spatial query result and reuses it while the pointer stays
/// within a small threshold and the document version remains unchanged.
class ArrowBindingTargetCache {
  // Cached misses use tighter thresholds to avoid stale "no target" states
  // while still de-duplicating repeated queries from tiny pointer jitter.
  static const _missThresholdScale = 0.75;

  DrawPoint? _lastPosition;
  double _lastDistance = 0;
  var _elementsVersion = -1;
  List<ElementState> _targets = const [];
  _ArrowBindingCandidateCacheEntry? _candidate;

  List<ElementState> get targets => _targets;

  bool isValid({
    required DrawPoint position,
    required double threshold,
    required double distance,
    required int elementsVersion,
  }) {
    final lastPosition = _lastPosition;
    if (lastPosition == null || threshold <= 0) {
      return false;
    }
    if (_elementsVersion != elementsVersion || _lastDistance != distance) {
      return false;
    }
    return _isWithinThreshold(
      from: lastPosition,
      to: position,
      threshold: threshold,
    );
  }

  void update({
    required DrawPoint position,
    required double distance,
    required int elementsVersion,
    required List<ElementState> targets,
  }) {
    _lastPosition = position;
    _lastDistance = distance;
    _elementsVersion = elementsVersion;
    _targets = targets;
  }

  /// Tries to reuse the most recent endpoint-binding candidate.
  ///
  /// Returns `(hasValue: false, value: null)` when no reusable candidate is
  /// available.
  ///
  /// `hasValue == true` means the cache has a definitive result for the query.
  /// The cached value itself can still be `null`, which represents a
  /// previously computed "no candidate" outcome.
  ({bool hasValue, ArrowBindingResult? value}) resolveCandidate({
    required DrawPoint position,
    required DrawPoint? referencePoint,
    required double positionThreshold,
    required double referenceThreshold,
    required int elementsVersion,
    required double snapDistance,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required bool shouldLookupBindings,
    required bool allowNewBinding,
    required bool hasBindableTargets,
    required ArrowBinding? preferredBinding,
    String? excludedElementId,
  }) {
    final candidate = _candidate;
    if (candidate == null) {
      return (hasValue: false, value: null);
    }
    if (!candidate.matchesQuery(
      elementsVersion: elementsVersion,
      snapDistance: snapDistance,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      shouldLookupBindings: shouldLookupBindings,
      allowNewBinding: allowNewBinding,
      hasBindableTargets: hasBindableTargets,
      preferredBinding: preferredBinding,
      excludedElementId: excludedElementId,
    )) {
      return (hasValue: false, value: null);
    }

    final isMiss = candidate.value == null;
    final effectivePositionThreshold = isMiss
        ? positionThreshold * _missThresholdScale
        : positionThreshold;
    if (!_isWithinThreshold(
      from: candidate.position,
      to: position,
      threshold: effectivePositionThreshold,
    )) {
      return (hasValue: false, value: null);
    }

    final effectiveReferenceThreshold = isMiss
        ? referenceThreshold * _missThresholdScale
        : referenceThreshold;
    if (!_referencesMatch(
      cachedReference: candidate.referencePoint,
      nextReference: referencePoint,
      threshold: effectiveReferenceThreshold,
    )) {
      return (hasValue: false, value: null);
    }

    return (hasValue: true, value: candidate.value);
  }

  /// Stores the latest endpoint-binding candidate query result.
  void cacheCandidate({
    required DrawPoint position,
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
    _candidate = _ArrowBindingCandidateCacheEntry(
      position: position,
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

  void reset() {
    _lastPosition = null;
    _lastDistance = 0;
    _elementsVersion = -1;
    _targets = const [];
    _candidate = null;
  }

  bool _isWithinThreshold({
    required DrawPoint from,
    required DrawPoint to,
    required double threshold,
  }) {
    if (threshold <= 0) {
      return false;
    }
    return from.distanceSquared(to) <= threshold * threshold;
  }

  bool _referencesMatch({
    required DrawPoint? cachedReference,
    required DrawPoint? nextReference,
    required double threshold,
  }) {
    if (cachedReference == null || nextReference == null) {
      return cachedReference == nextReference;
    }
    return _isWithinThreshold(
      from: cachedReference,
      to: nextReference,
      threshold: threshold,
    );
  }
}

class _ArrowBindingCandidateCacheEntry {
  const _ArrowBindingCandidateCacheEntry({
    required this.position,
    required this.referencePoint,
    required this.elementsVersion,
    required this.snapDistance,
    required this.arrowType,
    required this.arrowheadStyle,
    required this.shouldLookupBindings,
    required this.allowNewBinding,
    required this.hasBindableTargets,
    required this.preferredBinding,
    required this.excludedElementId,
    required this.value,
  });

  final DrawPoint position;
  final DrawPoint? referencePoint;
  final int elementsVersion;
  final double snapDistance;
  final ArrowType arrowType;
  final ArrowheadStyle arrowheadStyle;
  final bool shouldLookupBindings;
  final bool allowNewBinding;
  final bool hasBindableTargets;
  final ArrowBinding? preferredBinding;
  final String? excludedElementId;
  final ArrowBindingResult? value;

  bool matchesQuery({
    required int elementsVersion,
    required double snapDistance,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required bool shouldLookupBindings,
    required bool allowNewBinding,
    required bool hasBindableTargets,
    required ArrowBinding? preferredBinding,
    required String? excludedElementId,
  }) =>
      this.elementsVersion == elementsVersion &&
      this.snapDistance == snapDistance &&
      this.arrowType == arrowType &&
      this.arrowheadStyle == arrowheadStyle &&
      this.shouldLookupBindings == shouldLookupBindings &&
      this.allowNewBinding == allowNewBinding &&
      this.hasBindableTargets == hasBindableTargets &&
      this.preferredBinding == preferredBinding &&
      this.excludedElementId == excludedElementId;
}
