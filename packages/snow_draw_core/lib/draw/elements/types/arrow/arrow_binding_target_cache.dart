import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';

/// Reusable cache for nearby arrow-binding target queries.
///
/// Stores the last spatial query result and reuses it while the pointer stays
/// within a small threshold and the document version remains unchanged.
class ArrowBindingTargetCache {
  DrawPoint? _lastPosition;
  double _lastDistance = 0;
  var _elementsVersion = -1;
  List<ElementState> _targets = const [];

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

  void reset() {
    _lastPosition = null;
    _lastDistance = 0;
    _elementsVersion = -1;
    _targets = const [];
  }

  bool _isWithinThreshold({
    required DrawPoint from,
    required DrawPoint to,
    required double threshold,
  }) => from.distanceSquared(to) <= threshold * threshold;
}
