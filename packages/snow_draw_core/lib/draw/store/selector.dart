/// State selector.
///
/// Selects specific slices from full state to support fine-grained
/// subscriptions.
/// Listeners are only notified when the selected data changes to reduce UI
/// rebuilds.
abstract class StateSelector<S, T> {
  /// Select data from the state.
  T select(S state);

  /// Compare two selection results for equality.
  ///
  /// Uses the == operator by default. Subclasses can override for custom
  /// logic.
  bool equals(T prev, T next) => prev == next;
}

T Function(Object?) _wrapSelector<S, T>(T Function(S) selector) =>
    (state) => selector(state as S);

bool Function(Object?, Object?) _wrapEquals<T>(bool Function(T, T) equals) =>
    (prev, next) => equals(prev as T, next as T);

/// Simple functional selector.
///
/// Uses a function to select a state slice and optional custom equality.
class SimpleSelector<S, T> extends StateSelector<S, T> {
  SimpleSelector(T Function(S) selector, {bool Function(T, T)? equals})
    : _selector = _wrapSelector(selector),
      _equals = equals == null ? null : _wrapEquals(equals);
  final T Function(Object?) _selector;
  final bool Function(Object?, Object?)? _equals;

  @override
  T select(S state) => _selector(state);

  @override
  bool equals(T prev, T next) =>
      _equals?.call(prev, next) ?? super.equals(prev, next);
}

/// Combined selector.
///
/// Combines multiple selectors into one. If any child selector changes,
/// the combined result changes.
class CombinedSelector<S, T> extends StateSelector<S, T> {
  CombinedSelector(
    this._selectors,
    this._combiner, {
    bool Function(T, T)? equals,
  }) : _equals = equals == null ? null : _wrapEquals(equals);
  final List<StateSelector<S, dynamic>> _selectors;
  final T Function(List<dynamic>) _combiner;
  final bool Function(Object?, Object?)? _equals;

  @override
  T select(S state) {
    final results = _selectors.map((s) => s.select(state)).toList();
    return _combiner(results);
  }

  @override
  bool equals(T prev, T next) =>
      _equals?.call(prev, next) ?? super.equals(prev, next);
}

/// Memoized selector.
///
/// Caches the last selection result and recomputes only when input state
/// changes.
/// This is useful for expensive selectors.
class MemoizedSelector<S, T> extends StateSelector<S, T> {
  MemoizedSelector(this._selector);
  final StateSelector<S, T> _selector;
  S? _lastState;
  T? _lastResult;

  @override
  T select(S state) {
    if (_lastState == null || _lastState != state) {
      _lastState = state;
      _lastResult = _selector.select(state);
    }
    return _lastResult as T;
  }

  @override
  bool equals(T prev, T next) => _selector.equals(prev, next);

  /// Clear the cache.
  void clearCache() {
    _lastState = null;
    _lastResult = null;
  }
}
