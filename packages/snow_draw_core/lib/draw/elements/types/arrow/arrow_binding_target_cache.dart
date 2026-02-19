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
  DrawPoint? _candidatePosition;
  DrawPoint? _candidateReferencePoint;
  double _candidateSnapDistance = 0;
  var _candidateShouldLookupBindings = false;
  var _candidateAllowNewBinding = false;
  var _candidateHasBindableTargets = false;
  ArrowBinding? _candidatePreferredBinding;
  ArrowType? _candidateArrowType;
  ArrowheadStyle? _candidateArrowheadStyle;
  String? _candidateExcludedElementId;
  var _candidateElementsVersion = -1;
  var _hasCachedCandidate = false;
  ArrowBindingResult? _candidateValue;

  List<ElementState> get targets => _targets;

  bool isValid({
    required DrawPoint position,
    required double threshold,
    required double distance,
    required int elementsVersion,
  }) {
    if (_lastPosition == null) {
      return false;
    }
    if (_elementsVersion != elementsVersion) {
      return false;
    }
    if (_lastDistance != distance) {
      return false;
    }
    if (threshold <= 0) {
      return false;
    }
    return _lastPosition!.distanceSquared(position) <= threshold * threshold;
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
    if (!_hasCachedCandidate || _candidatePosition == null) {
      return (hasValue: false, value: null);
    }
    if (_candidateElementsVersion != elementsVersion ||
        _candidateSnapDistance != snapDistance ||
        _candidateArrowType != arrowType ||
        _candidateArrowheadStyle != arrowheadStyle ||
        _candidateShouldLookupBindings != shouldLookupBindings ||
        _candidateAllowNewBinding != allowNewBinding ||
        _candidateHasBindableTargets != hasBindableTargets ||
        _candidatePreferredBinding != preferredBinding ||
        _candidateExcludedElementId != excludedElementId) {
      return (hasValue: false, value: null);
    }

    final candidateIsMiss = _candidateValue == null;
    final effectivePositionThreshold = candidateIsMiss
        ? positionThreshold * _missThresholdScale
        : positionThreshold;
    if (effectivePositionThreshold <= 0) {
      return (hasValue: false, value: null);
    }
    if (_candidatePosition!.distanceSquared(position) >
        effectivePositionThreshold * effectivePositionThreshold) {
      return (hasValue: false, value: null);
    }

    final cachedReference = _candidateReferencePoint;
    if (cachedReference == null || referencePoint == null) {
      if (cachedReference != referencePoint) {
        return (hasValue: false, value: null);
      }
    } else {
      final effectiveReferenceThreshold = candidateIsMiss
          ? referenceThreshold * _missThresholdScale
          : referenceThreshold;
      if (effectiveReferenceThreshold <= 0) {
        return (hasValue: false, value: null);
      }
      if (cachedReference.distanceSquared(referencePoint) >
          effectiveReferenceThreshold * effectiveReferenceThreshold) {
        return (hasValue: false, value: null);
      }
    }

    return (hasValue: true, value: _candidateValue);
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
    _candidatePosition = position;
    _candidateReferencePoint = referencePoint;
    _candidateElementsVersion = elementsVersion;
    _candidateSnapDistance = snapDistance;
    _candidateArrowType = arrowType;
    _candidateArrowheadStyle = arrowheadStyle;
    _candidateShouldLookupBindings = shouldLookupBindings;
    _candidateAllowNewBinding = allowNewBinding;
    _candidateHasBindableTargets = hasBindableTargets;
    _candidatePreferredBinding = preferredBinding;
    _candidateExcludedElementId = excludedElementId;
    _hasCachedCandidate = true;
    _candidateValue = value;
  }

  /// Clears only the cached endpoint-binding candidate while keeping target
  /// spatial-query data.
  void clearCandidate() {
    _candidatePosition = null;
    _candidateReferencePoint = null;
    _candidateSnapDistance = 0;
    _candidateShouldLookupBindings = false;
    _candidateAllowNewBinding = false;
    _candidateHasBindableTargets = false;
    _candidatePreferredBinding = null;
    _candidateArrowType = null;
    _candidateArrowheadStyle = null;
    _candidateExcludedElementId = null;
    _candidateElementsVersion = -1;
    _hasCachedCandidate = false;
    _candidateValue = null;
  }

  void reset() {
    _lastPosition = null;
    _lastDistance = 0;
    _elementsVersion = -1;
    _targets = const [];
    clearCandidate();
  }
}
