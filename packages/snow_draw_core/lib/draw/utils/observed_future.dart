import 'dart:async';

/// Wraps a future and runs `onObserved` the first time consumers attach.
///
/// This is used by middleware pipelines to detect whether callers await or
/// return `next()`, which keeps pipeline ordering deterministic.
class ObservedFuture<T> implements Future<T> {
  ObservedFuture(this._delegate, {required void Function() onObserved})
    : _onObserved = onObserved;

  final Future<T> _delegate;
  final void Function() _onObserved;
  var _didObserve = false;

  void _markObserved() {
    if (_didObserve) {
      return;
    }
    _didObserve = true;
    _onObserved();
  }

  @override
  Stream<T> asStream() {
    _markObserved();
    return _delegate.asStream();
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    _markObserved();
    return _delegate.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    _markObserved();
    return _delegate.then<R>(onValue, onError: onError);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    _markObserved();
    return _delegate.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    _markObserved();
    return _delegate.whenComplete(action);
  }
}
