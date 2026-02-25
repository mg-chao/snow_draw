import '../types/draw_point.dart';

/// Tracks tap history and detects double-tap gestures.
final class DoubleTapTracker<T> {
  DoubleTapTracker({
    this.threshold = const Duration(milliseconds: 500),
    this.toleranceMultiplier = 2,
  }) : assert(!threshold.isNegative, 'threshold must not be negative'),
       assert(toleranceMultiplier >= 0, 'toleranceMultiplier must be >= 0');

  final Duration threshold;
  final double toleranceMultiplier;

  DateTime? _lastTapTime;
  DrawPoint? _lastTapPosition;
  T? _lastTapTarget;

  bool isDoubleTap({
    required T target,
    required DrawPoint position,
    required DateTime now,
    required double baseTolerance,
  }) {
    final lastTapTime = _lastTapTime;
    final lastTapPosition = _lastTapPosition;
    if (lastTapTime == null || lastTapPosition == null) {
      return false;
    }
    if (_lastTapTarget != target) {
      return false;
    }
    if (now.difference(lastTapTime) > threshold) {
      return false;
    }

    final tolerance = baseTolerance * toleranceMultiplier;
    return lastTapPosition.distanceSquared(position) <= tolerance * tolerance;
  }

  void recordTap({
    required T target,
    required DrawPoint position,
    required DateTime now,
  }) {
    _lastTapTarget = target;
    _lastTapPosition = position;
    _lastTapTime = now;
  }

  void clear() {
    _lastTapTarget = null;
    _lastTapPosition = null;
    _lastTapTime = null;
  }
}
