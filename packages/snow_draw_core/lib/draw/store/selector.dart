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

/// Simple functional selector.
///
/// Uses a function to select a state slice and optional custom equality.
class SimpleSelector<S, T> extends StateSelector<S, T> {
  SimpleSelector(T Function(S state) selector, {bool Function(T, T)? equals})
    : _selector = _wrapSelector(selector),
      _equals = _wrapEquals(equals);
  final T Function(Object?) _selector;
  final bool Function(Object?, Object?)? _equals;

  @override
  T select(S state) => _selector(state);

  @override
  bool equals(T prev, T next) =>
      _equals?.call(prev, next) ?? super.equals(prev, next);

  static T Function(Object?) _wrapSelector<S, T>(
    T Function(S state) selector,
  ) =>
      (state) => selector(state as S);

  static bool Function(Object?, Object?)? _wrapEquals<T>(
    bool Function(T previous, T next)? equals,
  ) => equals == null
      ? null
      : (previous, next) => equals(previous as T, next as T);
}
