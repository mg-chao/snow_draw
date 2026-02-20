import 'dart:math' as math;

import '../../draw/core/coordinates/element_space.dart';
import '../../draw/elements/core/element_hit_tester.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_point.dart';

/// Resolves the hit tester used for an element during eraser processing.
typedef EraserHitTesterResolver =
    ElementHitTester? Function(ElementState element);

/// Converts pointer movement into eraser-hit candidates.
///
/// The processor keeps per-pointer stroke continuity and samples each stroke
/// segment against point-local spatial-index queries, which avoids scanning
/// wide bounding rectangles during fast pointer motion.
class EraserStrokeProcessor {
  EraserStrokeProcessor({required EraserHitTesterResolver hitTesterResolver})
    : _hitTesterResolver = hitTesterResolver;

  static const _distanceSquaredEpsilon = 1e-9;
  static const _sampleStepFactor = 0.5;

  final EraserHitTesterResolver _hitTesterResolver;
  final _lastProcessedPositions = <int, DrawPoint>{};
  final _effectiveElementCache = <String, ElementState>{};
  DrawStateView? _cachedEffectiveStateView;

  /// Clears all stroke state.
  void reset() {
    _lastProcessedPositions.clear();
    _clearEffectiveElementCache();
  }

  /// Clears the cached last position for a pointer.
  void clearPointer(int pointerId) {
    _lastProcessedPositions.remove(pointerId);
  }

  /// Marks elements intersecting the latest pointer movement segment.
  ///
  /// Returns `true` when at least one new element was queued for preview.
  bool markElementsForErase({
    required int pointerId,
    required DrawPoint position,
    required DrawStateView stateView,
    required double tolerance,
    required bool Function(String elementId) isQueuedForPreview,
    required bool Function(ElementState element) queuePreview,
  }) {
    final previous = _lastProcessedPositions[pointerId];
    _lastProcessedPositions[pointerId] = position;
    final strokeStart = previous ?? position;
    final includeStart = previous == null;
    final resolvedTolerance = _sanitizeTolerance(tolerance);

    final document = stateView.state.domain.document;
    final elementById = document.elementMap;
    if (elementById.isEmpty) {
      _clearEffectiveElementCache();
      return false;
    }
    final hasPreviewOverrides = stateView.previewElementsById.isNotEmpty;
    _syncEffectiveElementCache(
      stateView: stateView,
      hasPreviewOverrides: hasPreviewOverrides,
    );

    var hasNewHits = false;
    _visitStrokeSamples(
      start: strokeStart,
      end: position,
      tolerance: resolvedTolerance,
      includeStart: includeStart,
      onSample: (sample) {
        if (_visitSampleCandidates(
          document: document,
          elementById: elementById,
          sample: sample,
          tolerance: resolvedTolerance,
          stateView: stateView,
          hasPreviewOverrides: hasPreviewOverrides,
          isQueuedForPreview: isQueuedForPreview,
          queuePreview: queuePreview,
        )) {
          hasNewHits = true;
        }
      },
    );

    return hasNewHits;
  }

  bool _visitSampleCandidates({
    required DocumentState document,
    required Map<String, ElementState> elementById,
    required DrawPoint sample,
    required double tolerance,
    required DrawStateView stateView,
    required bool hasPreviewOverrides,
    required bool Function(String elementId) isQueuedForPreview,
    required bool Function(ElementState element) queuePreview,
  }) {
    final candidates = document.spatialIndex.searchPointEntries(
      sample,
      tolerance,
      sortByZ: false,
    );
    var hasNewHits = false;
    for (final candidateEntry in candidates) {
      final candidateId = candidateEntry.id;
      if (isQueuedForPreview(candidateId)) {
        continue;
      }
      final candidate = elementById[candidateId];
      if (candidate == null) {
        continue;
      }
      final element = _resolveEffectiveElement(
        candidateId: candidateId,
        candidate: candidate,
        stateView: stateView,
        hasPreviewOverrides: hasPreviewOverrides,
      );
      if (!_isElementHitAtSample(
        element: element,
        sample: sample,
        tolerance: tolerance,
      )) {
        continue;
      }
      if (queuePreview(element)) {
        hasNewHits = true;
      }
    }
    return hasNewHits;
  }

  void _clearEffectiveElementCache() {
    _effectiveElementCache.clear();
    _cachedEffectiveStateView = null;
  }

  void _syncEffectiveElementCache({
    required DrawStateView stateView,
    required bool hasPreviewOverrides,
  }) {
    if (!hasPreviewOverrides) {
      _clearEffectiveElementCache();
      return;
    }
    if (!identical(_cachedEffectiveStateView, stateView)) {
      _effectiveElementCache.clear();
      _cachedEffectiveStateView = stateView;
    }
  }

  ElementState _resolveEffectiveElement({
    required String candidateId,
    required ElementState candidate,
    required DrawStateView stateView,
    required bool hasPreviewOverrides,
  }) {
    if (!hasPreviewOverrides) {
      return candidate;
    }
    return _effectiveElementCache[candidateId] ??= stateView.effectiveElement(
      candidate,
    );
  }

  double _sanitizeTolerance(double tolerance) {
    if (!tolerance.isFinite || tolerance <= 0) {
      return 0;
    }
    return tolerance;
  }

  bool _isElementHitAtSample({
    required ElementState element,
    required DrawPoint sample,
    required double tolerance,
  }) {
    final hitTester = _hitTesterResolver(element);
    if (hitTester != null) {
      return hitTester.hitTest(
        element: element,
        position: sample,
        tolerance: tolerance,
      );
    }
    return _isInsideRectWithTolerance(
      element: element,
      position: sample,
      tolerance: tolerance,
    );
  }

  bool _isInsideRectWithTolerance({
    required ElementState element,
    required DrawPoint position,
    required double tolerance,
  }) {
    final rect = element.rect;
    final local = element.rotation == 0
        ? position
        : ElementSpace(
            rotation: element.rotation,
            origin: rect.center,
          ).fromWorld(position);
    return local.x >= rect.minX - tolerance &&
        local.x <= rect.maxX + tolerance &&
        local.y >= rect.minY - tolerance &&
        local.y <= rect.maxY + tolerance;
  }

  void _visitStrokeSamples({
    required DrawPoint start,
    required DrawPoint end,
    required double tolerance,
    required bool includeStart,
    required void Function(DrawPoint sample) onSample,
  }) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final distanceSquared = dx * dx + dy * dy;
    if (!distanceSquared.isFinite ||
        distanceSquared <= _distanceSquaredEpsilon) {
      if (includeStart) {
        onSample(end);
      }
      return;
    }

    final sampleStep = tolerance * _sampleStepFactor;
    if (sampleStep <= 0) {
      if (includeStart) {
        onSample(start);
      }
      onSample(end);
      return;
    }

    final distance = math.sqrt(distanceSquared);
    final sampleCount = math.max(1, (distance / sampleStep).ceil());
    if (includeStart) {
      onSample(start);
    }
    for (var i = 1; i <= sampleCount; i++) {
      final t = i / sampleCount;
      onSample(DrawPoint(x: start.x + dx * t, y: start.y + dy * t));
    }
  }
}
