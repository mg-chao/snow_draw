import '../types/draw_point.dart';
import 'input_event.dart';

/// Tracks the latest pointer update payload and deduplicates no-op updates.
///
/// This guard treats updates as unchanged when x/y and modifiers are the same.
/// Pressure-only changes are intentionally ignored for edit/create update
/// dispatch; pressure-sensitive tools should rely on sampled batches instead.
class PointerUpdateGuard {
  DrawPoint? _lastPosition;
  KeyModifiers? _lastModifiers;

  /// Returns true when the update should be dispatched.
  ///
  /// Set [force] to true to bypass de-duplication and only refresh the guard
  /// snapshot.
  bool shouldDispatch({
    required DrawPoint position,
    required KeyModifiers modifiers,
    bool force = false,
  }) {
    final lastPosition = _lastPosition;
    if (!force &&
        lastPosition != null &&
        lastPosition.x == position.x &&
        lastPosition.y == position.y &&
        _lastModifiers == modifiers) {
      return false;
    }

    _lastPosition = position;
    _lastModifiers = modifiers;
    return true;
  }

  /// Clears the tracked update signature.
  void reset() {
    _lastPosition = null;
    _lastModifiers = null;
  }
}
