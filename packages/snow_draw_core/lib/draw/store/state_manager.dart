import '../models/draw_state.dart';

/// State manager.
///
/// Manages DrawStore state, including current and previous states.
/// This separates state logic from DrawStore to keep it focused and testable.
class StateManager {
  StateManager(DrawState initialState) : _current = initialState;
  DrawState _current;
  DrawState? _previous;

  /// Get the current state.
  DrawState get current => _current;

  /// Get the previous state.
  DrawState? get previous => _previous;

  /// Update state.
  ///
  /// If the new state matches the current state, do nothing.
  /// When updating, store the current state as the previous state.
  void update(DrawState newState) {
    if (newState == _current) {
      return;
    }
    _previous = _current;
    _current = newState;
  }

  /// Reset state.
  ///
  /// Force-set a new state even if it matches the current state.
  /// This may be needed in special cases.
  void reset(DrawState state) {
    _previous = _current;
    _current = state;
  }
}
