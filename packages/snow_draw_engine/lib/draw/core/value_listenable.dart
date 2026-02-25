import 'callbacks.dart';

/// Read-only value holder that notifies listeners when the value changes.
abstract interface class ValueListenable<T> {
  /// Current value.
  T get value;

  /// Registers [listener] for change notifications.
  void addListener(VoidCallback listener);

  /// Unregisters [listener].
  void removeListener(VoidCallback listener);
}

/// Mutable [ValueListenable] implementation for engine services.
final class ValueNotifier<T> implements ValueListenable<T> {
  /// Creates a notifier with an initial [value].
  ValueNotifier(this._value);

  final _listeners = <VoidCallback>[];
  T _value;

  @override
  T get value => _value;

  /// Updates the value and notifies listeners when changed.
  set value(T nextValue) {
    if (nextValue == _value) {
      return;
    }
    _value = nextValue;
    _notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    final snapshot = List<VoidCallback>.of(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }
}
