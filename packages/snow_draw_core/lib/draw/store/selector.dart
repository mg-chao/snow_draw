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
  SimpleSelector(T Function(S) selector, {bool Function(T, T)? equals})
    : _selector = ((state) => selector(state as S)),
      _equals = equals == null
          ? null
          : ((prev, next) => equals(prev as T, next as T));
  final T Function(Object?) _selector;
  final bool Function(Object?, Object?)? _equals;

  @override
  T select(S state) => _selector(state);

  @override
  bool equals(T prev, T next) =>
      _equals?.call(prev, next) ?? super.equals(prev, next);
}
