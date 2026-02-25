import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../models/element_state.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/snap_guides.dart';
import '../utils/selection_calculator.dart';

/// Axis for snapping calculations.
enum SnapAxis { x, y }

/// Anchor position on an axis: start (min), center, or end (max).
enum SnapAxisAnchor { start, center, end }

/// Result of a snap operation.
@immutable
class SnapResult {
  const SnapResult({this.dx = 0, this.dy = 0, this.guides = const []});

  /// Horizontal offset to apply for snapping.
  final double dx;

  /// Vertical offset to apply for snapping.
  final double dy;

  /// Visual guides to display for the active snaps.
  final List<SnapGuide> guides;

  /// Whether any snap was found.
  bool get hasSnap => dx != 0 || dy != 0;
}

/// Service for calculating object-to-object snapping in a drawing canvas.
///
/// Provides intelligent snapping when moving or resizing elements, supporting:
/// - **Point snaps**: Align element anchors (edges, centers) to other elements
/// - **Gap snaps**: Match spacing between elements for consistent layouts
///
/// ## Scoring Algorithm
///
/// When multiple snap candidates exist, the service uses weighted scoring to
/// select the best snap. Each candidate receives a strength score (0.0-1.0)
/// based on multiple factors, and the highest-scoring candidate wins.
///
/// ### Point Snap Scoring
/// Point snaps are scored by three weighted factors (summing to 1.0):
/// - **Distance (45%)**: How close the snap point is to the target position.
///   Closer snaps score higher.
/// - **Perpendicular alignment (40%)**: How well-aligned the elements are on
///   the cross-axis. Elements that overlap or are nearby score higher than
///   distant elements.
/// - **Anchor priority (15%)**: Preference for certain anchor combinations.
///   Center-to-center alignment is preferred over edge-to-edge, which is
///   preferred over mixed alignments.
///
/// ### Gap Snap Scoring
/// Gap snaps are scored by three weighted factors (summing to 1.0):
/// - **Distance (70%)**: How close the gap snap is to the target position.
/// - **Frequency (20%)**: How often this gap size appears among reference
///   elements. Common gap sizes are preferred for consistency.
/// - **Kind (10%)**: Center gaps (element centered in a gap) are slightly
///   preferred over side gaps (element edge aligned to gap).
///
/// Gap snaps are scaled by 0.9 relative to point snaps, giving point
/// alignment slight priority when both are equally strong.
class ObjectSnapService {
  const ObjectSnapService();

  /// Floating-point comparison tolerance.
  static const _epsilon = 0.0001;

  static const List<SnapAxisAnchor> _allAnchors = [
    SnapAxisAnchor.start,
    SnapAxisAnchor.center,
    SnapAxisAnchor.end,
  ];

  /// When comparing candidates, allow this percentage of snap distance as
  /// "slack" before distance becomes the deciding factor. This prevents
  /// flickering between candidates that are nearly equidistant.
  static const _priorityDistanceSlackFactor = 0.05;

  /// Maximum absolute slack value (caps the percentage-based slack).
  static const _priorityDistanceSlackMax = 0.5;

  /// Minimum strength difference required to prefer one candidate over another.
  /// Candidates within this threshold are compared by secondary factors.
  static const _strengthSlack = 0.05;

  /// Weight for snap distance in point snap scoring.
  /// Higher values make closer snaps more strongly preferred.
  static const _pointDistanceWeight = 0.45;

  /// Weight for perpendicular alignment in point snap scoring.
  /// Higher values prefer snapping to elements that are nearby on the
  /// cross-axis (e.g., horizontally adjacent when snapping vertically).
  static const _pointPerpendicularWeight = 0.4;

  /// Weight for anchor type priority in point snap scoring.
  /// Prefers center-to-center > same-anchor > mixed-anchor alignments.
  static const _pointAnchorWeight = 0.15;

  /// Weight for snap distance in gap snap scoring.
  static const _gapDistanceWeight = 0.7;

  /// Weight for gap frequency in gap snap scoring.
  /// Prefers gap sizes that appear multiple times among reference elements.
  static const _gapFrequencyWeight = 0.2;

  /// Weight for gap kind (center vs side) in gap snap scoring.
  static const _gapKindWeight = 0.1;

  /// Scale factor applied to gap snap strength relative to point snaps.
  /// Values < 1.0 give point snaps priority when strengths are similar.
  static const _gapStrengthScale = 0.9;

  /// Factor of element size used for perpendicular distance range.
  /// Larger values allow snapping to more distant elements on the cross-axis.
  static const _perpendicularSizeRangeFactor = 1.5;

  /// Factor of snap distance used for perpendicular distance range.
  static const _perpendicularSnapRangeFactor = 4.0;

  /// Maximum number of additional gap guides to show for matching gaps.
  static const _maxAssociatedGapGuides = 4;

  /// Maximum anchor priority value (used for normalization).
  static const _maxAnchorPriority = 3;

  /// Calculates snap offset for moving elements.
  ///
  /// Considers all anchor points (start, center, end) on both axes since
  /// the entire element is being moved.
  ///
  /// - [targetRect]: Bounding box of the element(s) being moved.
  /// - [referenceElements]: Other elements to snap against.
  /// - [snapDistance]: Maximum distance (in canvas units) to trigger a snap.
  /// - [enablePointSnaps]: Whether to consider point/anchor alignment.
  /// - [enableGapSnaps]: Whether to consider gap/spacing alignment.
  /// - [referenceAabbs]: Optional precomputed axis-aligned bounds for
  ///   [referenceElements]. When provided, this avoids rebuilding AABBs on
  ///   every pointer update.
  SnapResult snapMove({
    required DrawRect targetRect,
    required List<ElementState> referenceElements,
    required double snapDistance,
    List<DrawRect>? referenceAabbs,
    bool enablePointSnaps = true,
    bool enableGapSnaps = true,
  }) => snapRect(
    targetRect: targetRect,
    referenceElements: referenceElements,
    snapDistance: snapDistance,
    referenceAabbs: referenceAabbs,
    targetAnchorsX: _allAnchors,
    targetAnchorsY: _allAnchors,
    enablePointSnaps: enablePointSnaps,
    enableGapSnaps: enableGapSnaps,
  );

  /// Calculates snap offset for resizing elements.
  ///
  /// Only considers the anchors being dragged (e.g., when dragging the
  /// bottom-right corner, only end anchors are considered). Gap snapping
  /// is disabled during resize operations.
  ///
  /// - [targetRect]: Current bounding box during resize.
  /// - [referenceElements]: Other elements to snap against.
  /// - [snapDistance]: Maximum distance to trigger a snap.
  /// - [targetAnchorsX]: Which X anchors are being resized (e.g., `end` for
  ///   right edge).
  /// - [targetAnchorsY]: Which Y anchors are being resized.
  /// - [enablePointSnaps]: Whether to consider point/anchor alignment.
  /// - [referenceAabbs]: Optional precomputed axis-aligned bounds for
  ///   [referenceElements]. When provided, this avoids rebuilding AABBs on
  ///   every pointer update.
  SnapResult snapResize({
    required DrawRect targetRect,
    required List<ElementState> referenceElements,
    required double snapDistance,
    required List<SnapAxisAnchor> targetAnchorsX,
    required List<SnapAxisAnchor> targetAnchorsY,
    List<DrawRect>? referenceAabbs,
    bool enablePointSnaps = true,
  }) => snapRect(
    targetRect: targetRect,
    referenceElements: referenceElements,
    snapDistance: snapDistance,
    referenceAabbs: referenceAabbs,
    targetAnchorsX: targetAnchorsX,
    targetAnchorsY: targetAnchorsY,
    enablePointSnaps: enablePointSnaps,
    enableGapSnaps: false,
  );

  /// Engine snapping calculation that both [snapMove]
  /// and [snapResize] delegate to.
  ///
  /// The algorithm works as follows:
  /// 1. Build snap candidates for each axis (X and Y) independently
  /// 2. For point snaps: compare target anchors against reference
  /// element anchors
  /// 3. For gap snaps: find gaps between reference elements and check if target
  ///    can align to match those gaps
  /// 4. Score each candidate using weighted factors (see class documentation)
  /// 5. Select the best candidate for each axis
  /// 6. Generate visual guides for the selected snaps
  SnapResult snapRect({
    required DrawRect targetRect,
    required List<ElementState> referenceElements,
    required double snapDistance,
    required List<SnapAxisAnchor> targetAnchorsX,
    required List<SnapAxisAnchor> targetAnchorsY,
    List<DrawRect>? referenceAabbs,
    bool enablePointSnaps = true,
    bool enableGapSnaps = true,
  }) {
    if (snapDistance <= 0 ||
        referenceElements.isEmpty ||
        (!enablePointSnaps && !enableGapSnaps) ||
        (targetAnchorsX.isEmpty && targetAnchorsY.isEmpty)) {
      return const SnapResult();
    }
    final effectiveTargetAnchorsX = _deduplicateAnchors(targetAnchorsX);
    final effectiveTargetAnchorsY = _deduplicateAnchors(targetAnchorsY);
    final effectiveReferenceAabbs = _resolveReferenceAabbs(
      referenceElements,
      referenceAabbs,
    );
    final referenceRects = effectiveReferenceAabbs;

    final candidatesX = _buildAxisCandidates(
      axis: SnapAxis.x,
      targetRect: targetRect,
      referenceRects: referenceRects,
      targetAnchors: effectiveTargetAnchorsX,
      snapDistance: snapDistance,
      enablePointSnaps: enablePointSnaps,
      enableGapSnaps: enableGapSnaps,
    );
    final candidatesY = _buildAxisCandidates(
      axis: SnapAxis.y,
      targetRect: targetRect,
      referenceRects: referenceRects,
      targetAnchors: effectiveTargetAnchorsY,
      snapDistance: snapDistance,
      enablePointSnaps: enablePointSnaps,
      enableGapSnaps: enableGapSnaps,
    );

    final xCandidate = _selectBestCandidate(
      candidatesX,
      targetRect,
      snapDistance,
    );
    final yCandidate = _selectBestCandidate(
      candidatesY,
      targetRect,
      snapDistance,
    );

    final dx = xCandidate?.offset ?? 0;
    final dy = yCandidate?.offset ?? 0;
    final snappedRect = targetRect.translate(DrawPoint(x: dx, y: dy));

    final guides = <SnapGuide>[];
    final guideSet = <SnapGuide>{};
    void addGuide(SnapGuide guide) {
      if (guideSet.add(guide)) {
        guides.add(guide);
      }
    }

    _appendCandidateGuides(
      candidate: xCandidate,
      perpendicularCandidate: yCandidate,
      snappedRect: snappedRect,
      referenceRects: referenceRects,
      snapDistance: snapDistance,
      addGuide: addGuide,
    );
    _appendCandidateGuides(
      candidate: yCandidate,
      perpendicularCandidate: xCandidate,
      snappedRect: snappedRect,
      referenceRects: referenceRects,
      snapDistance: snapDistance,
      addGuide: addGuide,
    );

    return SnapResult(dx: dx, dy: dy, guides: guides);
  }

  static List<_AxisCandidate> _buildAxisCandidates({
    required SnapAxis axis,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
    required List<SnapAxisAnchor> targetAnchors,
    required double snapDistance,
    required bool enablePointSnaps,
    required bool enableGapSnaps,
  }) {
    if (targetAnchors.isEmpty) {
      return const <_AxisCandidate>[];
    }
    return <_AxisCandidate>[
      if (enablePointSnaps)
        ..._buildPointCandidates(
          axis: axis,
          targetRect: targetRect,
          referenceRects: referenceRects,
          targetAnchors: targetAnchors,
          snapDistance: snapDistance,
        ),
      if (enableGapSnaps)
        ..._buildGapCandidates(
          axis: axis,
          targetRect: targetRect,
          referenceRects: referenceRects,
          targetAnchors: targetAnchors,
          snapDistance: snapDistance,
        ),
    ];
  }

  static void _appendCandidateGuides({
    required _AxisCandidate? candidate,
    required _AxisCandidate? perpendicularCandidate,
    required DrawRect snappedRect,
    required List<DrawRect> referenceRects,
    required double snapDistance,
    required void Function(SnapGuide guide) addGuide,
  }) {
    if (candidate == null) {
      return;
    }

    for (final guide in _buildGuidesForCandidate(
      candidate,
      snappedRect,
      perpendicularCandidate,
    )) {
      addGuide(guide);
    }

    if (!_isGapCandidate(candidate)) {
      return;
    }

    for (final guide in _buildAssociatedGapGuides(
      candidate: candidate,
      targetRect: snappedRect,
      referenceRects: referenceRects,
      snapDistance: snapDistance,
    )) {
      addGuide(guide);
    }
  }

  /// Builds point snap candidates by comparing target anchors to reference
  /// anchors.
  ///
  /// For each combination of target anchor and reference anchor within snap
  /// distance, creates a candidate with the offset needed to align them.
  static List<_AxisCandidate> _buildPointCandidates({
    required SnapAxis axis,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
    required List<SnapAxisAnchor> targetAnchors,
    required double snapDistance,
  }) {
    final candidates = <_AxisCandidate>[];
    for (final rect in referenceRects) {
      final perpendicularDistance = _rectPerpendicularDistance(
        targetRect,
        rect,
        axis,
      );
      for (final targetAnchor in targetAnchors) {
        final targetPos = _anchorPosition(targetRect, axis, targetAnchor);
        for (final referenceAnchor in _allAnchors) {
          final referencePos = _anchorPosition(rect, axis, referenceAnchor);
          final offset = referencePos - targetPos;
          if (offset.abs() <= snapDistance) {
            candidates.add(
              _AxisCandidate.point(
                axis: axis,
                offset: offset,
                referenceRect: rect,
                targetAnchor: targetAnchor,
                referenceAnchor: referenceAnchor,
                perpendicularDistance: perpendicularDistance,
              ),
            );
          }
        }
      }
    }
    return candidates;
  }

  /// Builds gap snap candidates by analyzing spacing between
  /// reference elements.
  ///
  /// Gap snapping allows elements to match existing spacing patterns:
  /// - **Center gaps**: Position target centered between two reference elements
  /// - **Side gaps**: Position target edge at a consistent gap from a neighbor
  ///
  /// The algorithm:
  /// 1. Filter reference rects to those overlapping target on
  /// perpendicular axis
  /// 2. Sort by position and find gaps between adjacent elements
  /// 3. Bucket gaps by size to find common spacing values
  /// 4. Generate candidates for centering in gaps and matching gap sizes
  static List<_AxisCandidate> _buildGapCandidates({
    required SnapAxis axis,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
    required List<SnapAxisAnchor> targetAnchors,
    required double snapDistance,
  }) {
    final candidates = <_AxisCandidate>[];
    final allowCenter = targetAnchors.contains(SnapAxisAnchor.center);
    final filtered = _resolveGapReferenceRects(
      axis: axis,
      targetRect: targetRect,
      referenceRects: referenceRects,
    );
    if (filtered.length < 2) {
      return candidates;
    }

    final segments = _buildGapSegments(axis: axis, sortedRects: filtered);
    if (segments.isEmpty) {
      return candidates;
    }

    final gapBuckets = _gapSizeBuckets(segments);
    if (gapBuckets.isEmpty) {
      return candidates;
    }

    final targetCenter = _anchorPosition(
      targetRect,
      axis,
      SnapAxisAnchor.center,
    );
    final targetSize = _axisSize(targetRect, axis);

    final beforeNeighbor = _closestNeighbor(
      axis: axis,
      targetRect: targetRect,
      referenceRects: filtered,
      direction: _GapNeighborDirection.before,
    );
    final afterNeighbor = _closestNeighbor(
      axis: axis,
      targetRect: targetRect,
      referenceRects: filtered,
      direction: _GapNeighborDirection.after,
    );

    for (final segment in segments) {
      if (allowCenter) {
        final desiredCenter =
            (_axisMax(segment.before, axis) + _axisMin(segment.after, axis)) /
            2;
        final offset = desiredCenter - targetCenter;
        if (offset.abs() <= snapDistance) {
          final gapFrequency = _gapFrequencyFor(gapBuckets, segment.gap);
          candidates.add(
            _AxisCandidate.gapCenter(
              axis: axis,
              offset: offset,
              gapBeforeRect: segment.before,
              gapAfterRect: segment.after,
              gapSize: segment.gap,
              gapFrequency: gapFrequency,
            ),
          );
        }
      }

      // No side-based candidates here; those are derived from row spacing.
    }

    for (final bucket in gapBuckets) {
      final gap = bucket.size;
      final gapFrequency = bucket.count;
      _addGapSideCandidateFromNeighbor(
        candidates: candidates,
        axis: axis,
        targetRect: targetRect,
        targetSize: targetSize,
        snapDistance: snapDistance,
        neighbor: beforeNeighbor,
        gapSize: gap,
        gapFrequency: gapFrequency,
        gapSide: _GapSide.after,
      );
      _addGapSideCandidateFromNeighbor(
        candidates: candidates,
        axis: axis,
        targetRect: targetRect,
        targetSize: targetSize,
        snapDistance: snapDistance,
        neighbor: afterNeighbor,
        gapSize: gap,
        gapFrequency: gapFrequency,
        gapSide: _GapSide.before,
      );
    }

    return candidates;
  }

  /// Filters and sorts reference rects for gap calculations.
  ///
  /// Only includes rects that overlap the target on the perpendicular axis,
  /// ensuring gap calculations are between elements in the
  /// same "row" or "column".
  static List<DrawRect> _resolveGapReferenceRects({
    required SnapAxis axis,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
  }) {
    final filtered = <DrawRect>[
      for (final rect in referenceRects)
        if (_overlapsPerpendicular(rect, targetRect, axis)) rect,
    ];
    return filtered
      ..sort((a, b) => _axisMin(a, axis).compareTo(_axisMin(b, axis)));
  }

  static List<_GapSegment> _buildGapSegments({
    required SnapAxis axis,
    required List<DrawRect> sortedRects,
  }) {
    final segments = <_GapSegment>[];
    for (var i = 0; i < sortedRects.length - 1; i++) {
      final before = sortedRects[i];
      final after = sortedRects[i + 1];
      final gap = _axisMin(after, axis) - _axisMax(before, axis);
      if (gap > 0) {
        segments.add(_GapSegment(before: before, after: after, gap: gap));
      }
    }
    return segments;
  }

  static List<_GapSizeBucket> _gapSizeBuckets(List<_GapSegment> segments) {
    final buckets = <_GapSizeBucket>[];
    for (final segment in segments) {
      final gap = segment.gap;
      var index = -1;
      for (var i = 0; i < buckets.length; i++) {
        if ((buckets[i].size - gap).abs() <= _epsilon) {
          index = i;
          break;
        }
      }
      if (index == -1) {
        buckets.add(_GapSizeBucket(size: gap, count: 1));
      } else {
        final bucket = buckets[index];
        buckets[index] = _GapSizeBucket(
          size: bucket.size,
          count: bucket.count + 1,
        );
      }
    }
    return buckets;
  }

  static int _gapFrequencyFor(List<_GapSizeBucket> buckets, double gap) {
    for (final bucket in buckets) {
      if ((bucket.size - gap).abs() <= _epsilon) {
        return bucket.count;
      }
    }
    return 0;
  }

  static DrawRect? _closestNeighbor({
    required SnapAxis axis,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
    required _GapNeighborDirection direction,
  }) {
    final targetMin = _axisMin(targetRect, axis);
    final targetMax = _axisMax(targetRect, axis);
    DrawRect? closest;
    var bestDistance = double.infinity;

    for (final rect in referenceRects) {
      final distance = switch (direction) {
        _GapNeighborDirection.before => targetMin - _axisMax(rect, axis),
        _GapNeighborDirection.after => _axisMin(rect, axis) - targetMax,
      };
      if (distance < -_epsilon || distance > bestDistance) {
        continue;
      }
      bestDistance = distance;
      closest = rect;
    }

    return closest;
  }

  static void _addGapSideCandidateFromNeighbor({
    required List<_AxisCandidate> candidates,
    required SnapAxis axis,
    required DrawRect targetRect,
    required double targetSize,
    required double snapDistance,
    required DrawRect? neighbor,
    required double gapSize,
    required int gapFrequency,
    required _GapSide gapSide,
  }) {
    if (neighbor == null) {
      return;
    }
    final desiredStart = switch (gapSide) {
      _GapSide.after => _axisMax(neighbor, axis) + gapSize,
      _GapSide.before => _axisMin(neighbor, axis) - gapSize - targetSize,
    };
    _addGapSideCandidate(
      candidates: candidates,
      axis: axis,
      offset: desiredStart - _axisMin(targetRect, axis),
      snapDistance: snapDistance,
      referenceRect: neighbor,
      gapSize: gapSize,
      gapFrequency: gapFrequency,
      gapSide: gapSide,
    );
  }

  static void _addGapSideCandidate({
    required List<_AxisCandidate> candidates,
    required SnapAxis axis,
    required double offset,
    required double snapDistance,
    required DrawRect referenceRect,
    required double gapSize,
    required int gapFrequency,
    required _GapSide gapSide,
  }) {
    if (offset.abs() > snapDistance) {
      return;
    }
    candidates.add(
      _AxisCandidate.gapSide(
        axis: axis,
        offset: offset,
        referenceRect: referenceRect,
        gapSize: gapSize,
        gapFrequency: gapFrequency,
        gapSide: gapSide,
      ),
    );
  }

  /// Selects the best snap candidate from a list using weighted scoring.
  ///
  /// Candidates are compared by:
  /// 1. Strength score (weighted combination of factors) - higher wins
  /// 2. If strengths are within [_strengthSlack], use tiebreakers:
  ///    - Exact snaps (offset ~= 0) preferred
  ///    - Closer distance preferred
  ///    - Point snaps preferred over gap snaps
  ///    - For points: center alignment > edge > corner
  ///    - For gaps: higher frequency > center kind
  // Prefer strong snaps (nearby + locally aligned), then favor point/center
  // alignments to keep guides consistent when multiple candidates are
  // available.
  static _AxisCandidate? _selectBestCandidate(
    List<_AxisCandidate> candidates,
    DrawRect targetRect,
    double snapDistance,
  ) {
    _AxisCandidate? best;
    var bestStrength = 0.0;
    final distanceSlack = _distanceSlack(snapDistance);
    for (final candidate in candidates) {
      final candidateStrength = _candidateStrength(
        candidate,
        targetRect,
        snapDistance,
      );
      if (best == null ||
          _compareCandidates(
                candidate,
                best,
                candidateStrength,
                bestStrength,
                distanceSlack,
              ) >
              0) {
        best = candidate;
        bestStrength = candidateStrength;
      }
    }
    return best;
  }

  static double _distanceSlack(double snapDistance) {
    final slack = snapDistance * _priorityDistanceSlackFactor;
    return math.min(_priorityDistanceSlackMax, slack);
  }

  /// Calculates the strength score (0.0-1.0) for a snap candidate.
  ///
  /// For point snaps, combines:
  /// - Distance strength: 1.0 at offset=0, 0.0 at offset=snapDistance
  /// - Perpendicular strength: 1.0 when aligned, decreasing with
  /// cross-axis distance
  /// - Alignment strength: Based on anchor type priority
  ///
  /// For gap snaps, combines:
  /// - Distance strength (same as above)
  /// - Frequency strength: Higher for gap sizes that appear multiple times
  /// - Kind strength: Slightly higher for center gaps vs side gaps
  ///
  /// Gap snap scores are scaled by [_gapStrengthScale] to give point snaps
  /// slight priority when both are equally viable.
  static double _candidateStrength(
    _AxisCandidate candidate,
    DrawRect targetRect,
    double snapDistance,
  ) {
    final distanceStrength = _distanceStrength(
      candidate.distance,
      snapDistance,
    );
    return switch (candidate.kind) {
      _SnapKind.point => _clamp01(
        distanceStrength * _pointDistanceWeight +
            _perpendicularStrength(candidate, targetRect, snapDistance) *
                _pointPerpendicularWeight +
            _pointAlignmentStrength(candidate) * _pointAnchorWeight,
      ),
      _SnapKind.gapCenter || _SnapKind.gapSide => _clamp01(
        _gapStrengthScore(
              distanceStrength,
              candidate.gapFrequency ?? 0,
              isCenter: candidate.kind == _SnapKind.gapCenter,
            ) *
            _gapStrengthScale,
      ),
    };
  }

  static double _gapStrengthScore(
    double distanceStrength,
    int gapFrequency, {
    required bool isCenter,
  }) {
    final frequencyStrength = _gapFrequencyStrength(gapFrequency);
    final kindStrength = isCenter ? 1.0 : 0.85;
    return distanceStrength * _gapDistanceWeight +
        frequencyStrength * _gapFrequencyWeight +
        kindStrength * _gapKindWeight;
  }

  static double _distanceStrength(double distance, double snapDistance) =>
      (1 - (distance / snapDistance).clamp(0, 1)).toDouble();

  static double _perpendicularStrength(
    _AxisCandidate candidate,
    DrawRect targetRect,
    double snapDistance,
  ) {
    final referenceRect = candidate.referenceRect!;
    final perpendicularDistance = candidate.perpendicularDistance ?? 0;
    final range = _perpendicularRange(
      targetRect: targetRect,
      referenceRect: referenceRect,
      axis: candidate.axis,
      snapDistance: snapDistance,
    );
    if (range <= 0) {
      return 0;
    }
    final ratio = math.min(1, perpendicularDistance / range);
    return (1 - ratio).toDouble();
  }

  static double _perpendicularRange({
    required DrawRect targetRect,
    required DrawRect referenceRect,
    required SnapAxis axis,
    required double snapDistance,
  }) {
    final perpAxis = _perpendicularAxis(axis);
    final targetSize = _axisSize(targetRect, perpAxis);
    final referenceSize = _axisSize(referenceRect, perpAxis);
    final sizeRange =
        math.max(targetSize, referenceSize) * _perpendicularSizeRangeFactor;
    final snapRange = snapDistance * _perpendicularSnapRangeFactor;
    final range = math.max(sizeRange, snapRange);
    return math.max(range, snapDistance);
  }

  static double _pointAlignmentStrength(_AxisCandidate candidate) {
    final priority = _anchorPriority(
      candidate.targetAnchor!,
      candidate.referenceAnchor!,
    );
    return 1.0 - (priority / _maxAnchorPriority);
  }

  static double _gapFrequencyStrength(int gapFrequency) {
    if (gapFrequency <= 0) {
      return 0;
    }
    return 1.0 - (1.0 / (gapFrequency + 1));
  }

  static double _clamp01(double value) {
    if (value <= 0) {
      return 0;
    }
    if (value >= 1) {
      return 1;
    }
    return value;
  }

  static int _compareCandidates(
    _AxisCandidate left,
    _AxisCandidate right,
    double leftStrength,
    double rightStrength,
    double distanceSlack,
  ) {
    final strengthDelta = leftStrength - rightStrength;
    if (strengthDelta.abs() > _strengthSlack) {
      return strengthDelta > 0 ? 1 : -1;
    }

    final leftExact = _isExact(left.offset);
    final rightExact = _isExact(right.offset);
    if (leftExact != rightExact) {
      return leftExact ? 1 : -1;
    }

    final distanceDelta = left.distance - right.distance;
    if (distanceDelta.abs() > distanceSlack) {
      return distanceDelta < 0 ? 1 : -1;
    }

    final leftKindPriority = _snapKindPriority(left.kind);
    final rightKindPriority = _snapKindPriority(right.kind);
    if (leftKindPriority != rightKindPriority) {
      return leftKindPriority < rightKindPriority ? 1 : -1;
    }

    final kindSpecificComparison = _compareKindSpecificTieBreakers(left, right);
    if (kindSpecificComparison != 0) {
      return kindSpecificComparison;
    }

    if (distanceDelta.abs() > _epsilon) {
      return distanceDelta < 0 ? 1 : -1;
    }

    return 0;
  }

  static int _snapKindPriority(_SnapKind kind) =>
      kind == _SnapKind.point ? 0 : 1;

  static int _compareKindSpecificTieBreakers(
    _AxisCandidate left,
    _AxisCandidate right,
  ) {
    if (left.kind == _SnapKind.point && right.kind == _SnapKind.point) {
      return _comparePointCandidates(left, right);
    }
    if (left.kind != _SnapKind.point && right.kind != _SnapKind.point) {
      return _compareGapCandidates(left, right);
    }
    return 0;
  }

  static int _comparePointCandidates(
    _AxisCandidate left,
    _AxisCandidate right,
  ) {
    final leftPointPriority = _pointPriority(left);
    final rightPointPriority = _pointPriority(right);
    if (leftPointPriority != rightPointPriority) {
      return leftPointPriority < rightPointPriority ? 1 : -1;
    }

    final leftPerpendicularDistance =
        left.perpendicularDistance ?? double.infinity;
    final rightPerpendicularDistance =
        right.perpendicularDistance ?? double.infinity;
    final perpendicularDelta =
        leftPerpendicularDistance - rightPerpendicularDistance;
    if (perpendicularDelta.abs() <= _epsilon) {
      return 0;
    }
    return perpendicularDelta < 0 ? 1 : -1;
  }

  static int _compareGapCandidates(_AxisCandidate left, _AxisCandidate right) {
    final leftGapFrequency = left.gapFrequency ?? 0;
    final rightGapFrequency = right.gapFrequency ?? 0;
    if (leftGapFrequency != rightGapFrequency) {
      return leftGapFrequency > rightGapFrequency ? 1 : -1;
    }

    final leftGapKindPriority = _gapKindPriority(left);
    final rightGapKindPriority = _gapKindPriority(right);
    if (leftGapKindPriority == rightGapKindPriority) {
      return 0;
    }
    return leftGapKindPriority < rightGapKindPriority ? 1 : -1;
  }

  static int _pointPriority(_AxisCandidate candidate) =>
      _anchorPriority(candidate.targetAnchor!, candidate.referenceAnchor!);

  static int _gapKindPriority(_AxisCandidate candidate) =>
      candidate.kind == _SnapKind.gapCenter ? 0 : 1;

  static List<SnapGuide> _buildGuidesForCandidate(
    _AxisCandidate candidate,
    DrawRect targetRect,
    _AxisCandidate? perpendicularCandidate,
  ) {
    if (candidate.kind == _SnapKind.gapCenter) {
      final splitGuides = _buildSplitGapCenterGuides(
        candidate: candidate,
        targetRect: targetRect,
      );
      if (splitGuides.isNotEmpty) {
        return splitGuides;
      }
    }
    return [_buildGuide(candidate, targetRect, perpendicularCandidate)];
  }

  static SnapGuide _buildGuide(
    _AxisCandidate candidate,
    DrawRect targetRect,
    _AxisCandidate? perpendicularCandidate,
  ) => switch (candidate.kind) {
    _SnapKind.point => _buildPointGuide(
      candidate,
      targetRect,
      perpendicularCandidate,
    ),
    _SnapKind.gapCenter ||
    _SnapKind.gapSide => _buildGapGuide(candidate, targetRect),
  };

  static bool _isGapCandidate(_AxisCandidate candidate) =>
      candidate.kind == _SnapKind.gapCenter ||
      candidate.kind == _SnapKind.gapSide;

  static List<SnapGuide> _buildAssociatedGapGuides({
    required _AxisCandidate candidate,
    required DrawRect targetRect,
    required List<DrawRect> referenceRects,
    required double snapDistance,
  }) {
    final gapSize = candidate.gapSize!;
    final gapTolerance = math.max(_epsilon, _distanceSlack(snapDistance));

    final filtered = _resolveGapReferenceRects(
      axis: candidate.axis,
      targetRect: targetRect,
      referenceRects: referenceRects,
    );
    if (filtered.length < 2) {
      return const [];
    }

    final segments = _buildGapSegments(
      axis: candidate.axis,
      sortedRects: filtered,
    );
    if (segments.isEmpty) {
      return const [];
    }

    final matchingSegments = <_GapSegment>[];
    for (final segment in segments) {
      if ((segment.gap - gapSize).abs() > gapTolerance) {
        continue;
      }
      if (_matchesGapSegment(candidate, segment)) {
        continue;
      }
      matchingSegments.add(segment);
    }
    if (matchingSegments.isEmpty) {
      return const [];
    }

    matchingSegments.sort(
      (a, b) => _gapSegmentDistanceToTarget(
        a,
        targetRect,
        candidate.axis,
      ).compareTo(_gapSegmentDistanceToTarget(b, targetRect, candidate.axis)),
    );

    final guides = <SnapGuide>[];
    final limit = math.min(_maxAssociatedGapGuides, matchingSegments.length);
    for (var i = 0; i < limit; i++) {
      final segment = matchingSegments[i];
      final segmentCandidate = _AxisCandidate.gapCenter(
        axis: candidate.axis,
        offset: 0,
        gapBeforeRect: segment.before,
        gapAfterRect: segment.after,
        gapSize: gapSize,
        gapFrequency: candidate.gapFrequency,
      );
      guides.add(_buildGapGuide(segmentCandidate, targetRect));
    }
    return guides;
  }

  static bool _matchesGapSegment(
    _AxisCandidate candidate,
    _GapSegment segment,
  ) {
    if (candidate.kind != _SnapKind.gapCenter) {
      return false;
    }
    return candidate.gapBeforeRect == segment.before &&
        candidate.gapAfterRect == segment.after;
  }

  static double _gapSegmentDistanceToTarget(
    _GapSegment segment,
    DrawRect targetRect,
    SnapAxis axis,
  ) {
    final targetCenter = _axisCenter(targetRect, axis);
    final segmentCenter =
        (_axisMax(segment.before, axis) + _axisMin(segment.after, axis)) / 2;
    return (segmentCenter - targetCenter).abs();
  }

  static SnapGuide _buildPointGuide(
    _AxisCandidate candidate,
    DrawRect targetRect,
    _AxisCandidate? perpendicularCandidate,
  ) {
    final referenceRect = candidate.referenceRect!;
    final snapPos = _anchorPosition(
      referenceRect,
      candidate.axis,
      candidate.referenceAnchor!,
    );
    final markers = _resolvePointMarkers(
      candidate: candidate,
      targetRect: targetRect,
      referenceRect: referenceRect,
      snapPos: snapPos,
      perpendicularCandidate: perpendicularCandidate,
    );

    if (candidate.axis == SnapAxis.x) {
      final minY = math.min(referenceRect.minY, targetRect.minY);
      final maxY = math.max(referenceRect.maxY, targetRect.maxY);
      final start = DrawPoint(x: snapPos, y: minY);
      final end = DrawPoint(x: snapPos, y: maxY);
      return SnapGuide(
        kind: SnapGuideKind.point,
        axis: SnapGuideAxis.vertical,
        start: start,
        end: end,
        markers: markers,
      );
    }

    final minX = math.min(referenceRect.minX, targetRect.minX);
    final maxX = math.max(referenceRect.maxX, targetRect.maxX);
    final start = DrawPoint(x: minX, y: snapPos);
    final end = DrawPoint(x: maxX, y: snapPos);
    return SnapGuide(
      kind: SnapGuideKind.point,
      axis: SnapGuideAxis.horizontal,
      start: start,
      end: end,
      markers: markers,
    );
  }

  static SnapGuide _buildGapGuide(
    _AxisCandidate candidate,
    DrawRect targetRect,
  ) {
    final (start, end) = _gapBounds(candidate, targetRect);
    return _buildGapGuideForBounds(
      axis: candidate.axis,
      targetRect: targetRect,
      start: start,
      end: end,
      gapSize: candidate.gapSize!,
    );
  }

  static List<SnapGuide> _buildSplitGapCenterGuides({
    required _AxisCandidate candidate,
    required DrawRect targetRect,
  }) {
    final before = candidate.gapBeforeRect!;
    final after = candidate.gapAfterRect!;
    final axis = candidate.axis;
    final gapStart = _axisMax(before, axis);
    final gapEnd = _axisMin(after, axis);
    final targetStart = _axisMin(targetRect, axis);
    final targetEnd = _axisMax(targetRect, axis);

    if (targetStart <= gapStart + _epsilon || targetEnd >= gapEnd - _epsilon) {
      return const [];
    }

    final gapSize = candidate.gapSize!;
    return [
      _buildGapGuideForBounds(
        axis: axis,
        targetRect: targetRect,
        start: gapStart,
        end: targetStart,
        gapSize: gapSize,
      ),
      _buildGapGuideForBounds(
        axis: axis,
        targetRect: targetRect,
        start: targetEnd,
        end: gapEnd,
        gapSize: gapSize,
      ),
    ];
  }

  static SnapGuide _buildGapGuideForBounds({
    required SnapAxis axis,
    required DrawRect targetRect,
    required double start,
    required double end,
    required double gapSize,
  }) {
    if (axis == SnapAxis.x) {
      final y = targetRect.centerY;
      final startPoint = DrawPoint(x: start, y: y);
      final endPoint = DrawPoint(x: end, y: y);
      return SnapGuide(
        kind: SnapGuideKind.gap,
        axis: SnapGuideAxis.horizontal,
        start: startPoint,
        end: endPoint,
        markers: [startPoint, endPoint],
        label: gapSize,
      );
    }

    final x = targetRect.centerX;
    final startPoint = DrawPoint(x: x, y: start);
    final endPoint = DrawPoint(x: x, y: end);
    return SnapGuide(
      kind: SnapGuideKind.gap,
      axis: SnapGuideAxis.vertical,
      start: startPoint,
      end: endPoint,
      markers: [startPoint, endPoint],
      label: gapSize,
    );
  }

  static (double, double) _gapBounds(
    _AxisCandidate candidate,
    DrawRect targetRect,
  ) {
    final axis = candidate.axis;
    if (candidate.kind == _SnapKind.gapCenter) {
      final before = candidate.gapBeforeRect!;
      final after = candidate.gapAfterRect!;
      return (_axisMax(before, axis), _axisMin(after, axis));
    }
    if (candidate.kind == _SnapKind.gapSide) {
      final referenceRect = candidate.referenceRect!;
      if (candidate.gapSide == _GapSide.after) {
        return (_axisMax(referenceRect, axis), _axisMin(targetRect, axis));
      }
      return (_axisMax(targetRect, axis), _axisMin(referenceRect, axis));
    }
    throw StateError('Gap bounds requested for a non-gap candidate.');
  }

  static bool _overlapsPerpendicular(DrawRect a, DrawRect b, SnapAxis axis) {
    if (axis == SnapAxis.x) {
      return a.maxY >= b.minY && a.minY <= b.maxY;
    }
    return a.maxX >= b.minX && a.minX <= b.maxX;
  }

  static double _anchorPosition(
    DrawRect rect,
    SnapAxis axis,
    SnapAxisAnchor anchor,
  ) => switch (axis) {
    SnapAxis.x => switch (anchor) {
      SnapAxisAnchor.start => rect.minX,
      SnapAxisAnchor.center => rect.centerX,
      SnapAxisAnchor.end => rect.maxX,
    },
    SnapAxis.y => switch (anchor) {
      SnapAxisAnchor.start => rect.minY,
      SnapAxisAnchor.center => rect.centerY,
      SnapAxisAnchor.end => rect.maxY,
    },
  };

  static double _axisMin(DrawRect rect, SnapAxis axis) =>
      axis == SnapAxis.x ? rect.minX : rect.minY;

  static double _axisMax(DrawRect rect, SnapAxis axis) =>
      axis == SnapAxis.x ? rect.maxX : rect.maxY;

  static double _axisCenter(DrawRect rect, SnapAxis axis) =>
      axis == SnapAxis.x ? rect.centerX : rect.centerY;

  static double _axisSize(DrawRect rect, SnapAxis axis) =>
      axis == SnapAxis.x ? rect.width : rect.height;

  static SnapAxis _perpendicularAxis(SnapAxis axis) =>
      axis == SnapAxis.x ? SnapAxis.y : SnapAxis.x;

  static double _rectPerpendicularDistance(
    DrawRect a,
    DrawRect b,
    SnapAxis axis,
  ) {
    if (axis == SnapAxis.x) {
      if (a.maxY < b.minY) {
        return b.minY - a.maxY;
      }
      if (b.maxY < a.minY) {
        return a.minY - b.maxY;
      }
      return 0;
    }
    if (a.maxX < b.minX) {
      return b.minX - a.maxX;
    }
    if (b.maxX < a.minX) {
      return a.minX - b.maxX;
    }
    return 0;
  }

  static List<DrawPoint> _resolvePointMarkers({
    required _AxisCandidate candidate,
    required DrawRect targetRect,
    required DrawRect referenceRect,
    required double snapPos,
    required _AxisCandidate? perpendicularCandidate,
  }) {
    final axis = candidate.axis;
    final perpendicularAxis = _perpendicularAxis(axis);
    final targetPerpAnchor =
        perpendicularCandidate != null &&
            perpendicularCandidate.axis == perpendicularAxis
        ? perpendicularCandidate.targetAnchor
        : null;
    final referencePerpAnchor =
        perpendicularCandidate != null &&
            perpendicularCandidate.axis == perpendicularAxis &&
            perpendicularCandidate.referenceRect == referenceRect
        ? perpendicularCandidate.referenceAnchor
        : null;
    final targetPerp = targetPerpAnchor != null
        ? _anchorPosition(targetRect, perpendicularAxis, targetPerpAnchor)
        : _axisCenter(targetRect, perpendicularAxis);
    final referencePerp = referencePerpAnchor != null
        ? _anchorPosition(referenceRect, perpendicularAxis, referencePerpAnchor)
        : _axisCenter(referenceRect, perpendicularAxis);

    final primary = axis == SnapAxis.x
        ? DrawPoint(x: snapPos, y: targetPerp)
        : DrawPoint(x: targetPerp, y: snapPos);
    final secondary = axis == SnapAxis.x
        ? DrawPoint(x: snapPos, y: referencePerp)
        : DrawPoint(x: referencePerp, y: snapPos);
    if (primary == secondary) {
      return [primary];
    }
    return [primary, secondary];
  }

  static int _anchorPriority(SnapAxisAnchor target, SnapAxisAnchor reference) {
    if (target == SnapAxisAnchor.center && reference == SnapAxisAnchor.center) {
      return 0;
    }
    if (target == reference) {
      return 1;
    }
    if (target == SnapAxisAnchor.center || reference == SnapAxisAnchor.center) {
      return 2;
    }
    return 3;
  }

  static bool _isExact(double offset) => offset.abs() <= _epsilon;

  static List<DrawRect> _buildElementAabbs(List<ElementState> elements) => [
    for (final element in elements)
      SelectionCalculator.computeElementWorldAabb(element),
  ];

  static List<DrawRect> _resolveReferenceAabbs(
    List<ElementState> referenceElements,
    List<DrawRect>? referenceAabbs,
  ) =>
      referenceAabbs != null &&
          referenceAabbs.length == referenceElements.length
      ? referenceAabbs
      : _buildElementAabbs(referenceElements);

  /// Builds reusable axis-aligned bounds for [referenceElements].
  ///
  /// Callers running high-frequency snapping loops (create/move/resize) can
  /// compute this once per session and pass it to [snapRect], [snapMove], or
  /// [snapResize] via `referenceAabbs`.
  static List<DrawRect> buildReferenceAabbs(
    List<ElementState> referenceElements,
  ) => List<DrawRect>.unmodifiable(_buildElementAabbs(referenceElements));

  static List<SnapAxisAnchor> _deduplicateAnchors(
    List<SnapAxisAnchor> anchors,
  ) {
    if (anchors.length < 2) {
      return anchors;
    }

    final seen = <SnapAxisAnchor>{};
    final deduplicated = <SnapAxisAnchor>[];
    var hasDuplicate = false;
    for (final anchor in anchors) {
      if (!seen.add(anchor)) {
        hasDuplicate = true;
        continue;
      }
      deduplicated.add(anchor);
    }
    return hasDuplicate ? deduplicated : anchors;
  }
}

const objectSnapService = ObjectSnapService();

/// Type of snap: point alignment or gap alignment.
enum _SnapKind { point, gapCenter, gapSide }

/// Which side of a reference element a gap snap is relative to.
enum _GapSide { before, after }

/// Direction to search for neighboring elements.
enum _GapNeighborDirection { before, after }

/// A candidate snap for one axis, with all data needed for scoring
/// and guide generation.
@immutable
class _AxisCandidate {
  const _AxisCandidate.point({
    required this.axis,
    required this.offset,
    required this.referenceRect,
    required this.targetAnchor,
    required this.referenceAnchor,
    this.perpendicularDistance,
  }) : kind = _SnapKind.point,
       gapBeforeRect = null,
       gapAfterRect = null,
       gapSize = null,
       gapSide = null,
       gapFrequency = null;

  const _AxisCandidate.gapCenter({
    required this.axis,
    required this.offset,
    required this.gapBeforeRect,
    required this.gapAfterRect,
    required this.gapSize,
    required this.gapFrequency,
  }) : kind = _SnapKind.gapCenter,
       referenceRect = null,
       targetAnchor = null,
       referenceAnchor = null,
       perpendicularDistance = null,
       gapSide = null;

  const _AxisCandidate.gapSide({
    required this.axis,
    required this.offset,
    required this.referenceRect,
    required this.gapSize,
    required this.gapFrequency,
    required this.gapSide,
  }) : kind = _SnapKind.gapSide,
       gapBeforeRect = null,
       gapAfterRect = null,
       targetAnchor = null,
       referenceAnchor = null,
       perpendicularDistance = null;

  final SnapAxis axis;
  final double offset;
  final _SnapKind kind;

  final DrawRect? referenceRect;
  final SnapAxisAnchor? targetAnchor;
  final SnapAxisAnchor? referenceAnchor;
  final double? perpendicularDistance;

  final DrawRect? gapBeforeRect;
  final DrawRect? gapAfterRect;
  final double? gapSize;
  final _GapSide? gapSide;
  final int? gapFrequency;

  double get distance => offset.abs();
}

/// A gap between two adjacent reference elements.
@immutable
class _GapSegment {
  const _GapSegment({
    required this.before,
    required this.after,
    required this.gap,
  });
  final DrawRect before;
  final DrawRect after;
  final double gap;
}

/// Bucket for grouping gaps of similar size, tracking frequency.
@immutable
class _GapSizeBucket {
  const _GapSizeBucket({required this.size, required this.count});
  final double size;
  final int count;
}
