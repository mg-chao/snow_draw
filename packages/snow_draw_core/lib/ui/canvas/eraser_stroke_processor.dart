import 'dart:math' as math;

import '../../draw/core/coordinates/element_space.dart';
import '../../draw/elements/core/element_hit_tester.dart';
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

  final EraserHitTesterResolver _hitTesterResolver;
  final _lastProcessedPositions = <int, DrawPoint>{};
  final _effectiveElementCache = <String, ElementState>{};
  DrawStateView? _cachedEffectiveStateView;

  /// Clears all stroke state.
  void reset() {
    _lastProcessedPositions.clear();
    _effectiveElementCache.clear();
    _cachedEffectiveStateView = null;
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
    final resolvedTolerance = _resolveSampleTolerance(tolerance);

    final document = stateView.state.domain.document;
    final hasPreviewOverrides = stateView.previewElementsById.isNotEmpty;
    if (!hasPreviewOverrides) {
      _effectiveElementCache.clear();
      _cachedEffectiveStateView = null;
    } else if (!identical(_cachedEffectiveStateView, stateView)) {
      _effectiveElementCache.clear();
      _cachedEffectiveStateView = stateView;
    }

    var hasNewHits = false;
    _visitStrokeSamples(
      start: strokeStart,
      end: position,
      tolerance: resolvedTolerance,
      includeStart: includeStart,
      onSample: (sample) {
        document.visitElementsAtPoint(sample, resolvedTolerance, (candidate) {
          final candidateId = candidate.id;
          if (isQueuedForPreview(candidateId)) {
            return true;
          }

          final element = hasPreviewOverrides
              ? (_effectiveElementCache[candidateId] ??= stateView
                    .effectiveElement(candidate))
              : candidate;
          if (_isElementHitAtSample(
            element: element,
            sample: sample,
            tolerance: resolvedTolerance,
          )) {
            if (queuePreview(element)) {
              hasNewHits = true;
            }
          }
          return true;
        });
      },
    );

    return hasNewHits;
  }

  double _resolveSampleTolerance(double tolerance) {
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
    return hitTester?.hitTest(
          element: element,
          position: sample,
          tolerance: tolerance,
        ) ??
        _isInsideRectWithTolerance(
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

    final sampleStep = tolerance * 0.5;
    if (!sampleStep.isFinite || sampleStep <= 0) {
      if (includeStart) {
        onSample(start);
      }
      onSample(end);
      return;
    }

    final distance = math.sqrt(distanceSquared);
    final sampleCountValue = distance / sampleStep;
    if (!sampleCountValue.isFinite) {
      if (includeStart) {
        onSample(start);
      }
      onSample(end);
      return;
    }
    final sampleCount = math.max(1, sampleCountValue.ceil());
    if (includeStart) {
      onSample(start);
    }
    for (var i = 1; i <= sampleCount; i++) {
      final t = i / sampleCount;
      onSample(DrawPoint(x: start.x + dx * t, y: start.y + dy * t));
    }
  }
}
