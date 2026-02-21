import '../models/draw_state.dart';

/// Manages the current and previous [DrawState] values.
class StateManager {
  StateManager(this._current);

  DrawState _current;
  DrawState? _previous;

  DrawState get current => _current;

  DrawState? get previous => _previous;

  /// Updates state when [newState] differs from [current].
  void update(DrawState newState) {
    if (newState == _current) {
      return;
    }
    _setState(newState);
  }

  /// Replaces [current], even when [state] equals the existing value.
  void reset(DrawState state) => _setState(state);

  void _setState(DrawState state) {
    _previous = _current;
    _current = state;
  }
}
