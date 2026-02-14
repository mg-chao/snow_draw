import 'dart:async';

import 'package:meta/meta.dart';

/// Base class for events.
@immutable
abstract class DrawEvent {
  const DrawEvent();
}

/// Event bus.
///
/// Provides type-safe event publishing and subscriptions.
class EventBus {
  EventBus() : _controller = StreamController<DrawEvent>.broadcast();

  final StreamController<DrawEvent> _controller;
  final Map<Type, _TypedChannelBase> _typedChannels = {};
  Future<void>? _disposeFuture;
  var _activeTypedChannels = 0;

  /// Event stream.
  Stream<DrawEvent> get stream => _controller.stream;

  /// Whether there are active listeners.
  bool get hasListeners =>
      !_controller.isClosed &&
      (_controller.hasListener || _activeTypedChannels > 0);

  /// Whether the event bus has been disposed.
  bool get isDisposed => _controller.isClosed;

  /// Whether listeners can receive events of type [T].
  ///
  /// This includes:
  /// - direct listeners to [T]
  /// - listeners to supertypes of [T] (for example, [DrawEvent])
  /// - listeners to the untyped [stream]
  bool hasListenersFor<T extends DrawEvent>() {
    if (_controller.isClosed) {
      return false;
    }
    if (_controller.hasListener) {
      return true;
    }
    for (final channel in _typedChannels.values) {
      if (channel.hasListeners && channel.acceptsType<T>()) {
        return true;
      }
    }
    return false;
  }

  /// Whether listeners can receive this concrete [event] instance.
  bool hasListenersForEvent(DrawEvent event) {
    if (_controller.isClosed) {
      return false;
    }
    if (_controller.hasListener) {
      return true;
    }
    for (final channel in _typedChannels.values) {
      if (channel.hasListeners && channel.matches(event)) {
        return true;
      }
    }
    return false;
  }

  /// Emit an event.
  void emit(DrawEvent event) {
    tryEmit(event);
  }

  /// Emit an event and report whether it was dispatched.
  bool tryEmit(DrawEvent event) {
    if (_controller.isClosed || !hasListenersForEvent(event)) {
      return false;
    }

    if (_controller.hasListener) {
      _controller.add(event);
    }
    for (final channel in _typedChannels.values) {
      channel.emit(event);
    }
    return true;
  }

  /// Builds and emits an event only when listeners can receive it.
  bool emitLazy<T extends DrawEvent>(T Function() eventFactory) {
    if (!hasListenersFor<T>()) {
      return false;
    }
    return tryEmit(eventFactory());
  }

  /// Typed stream for a specific event type.
  Stream<T> streamOf<T extends DrawEvent>() {
    final cached = _typedChannels[T];
    if (cached != null) {
      return cached.stream as Stream<T>;
    }

    if (_controller.isClosed) {
      return Stream<T>.empty();
    }

    final channel = _TypedChannel<T>(
      onFirstListener: _handleTypedListenerAttached,
      onLastListener: _handleTypedListenerDetached,
    );
    _typedChannels[T] = channel;
    return channel.stream;
  }

  /// Subscribe to a specific event type.
  StreamSubscription<T> on<T extends DrawEvent>(
    void Function(T event) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => streamOf<T>().listen(
    handler,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  /// Close the event bus.
  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) {
      return pending;
    }

    final closing = _closeAllControllers();
    _disposeFuture = closing;
    return closing;
  }

  Future<void> _closeAllControllers() async {
    final futures = <Future<void>>[_controller.close()];
    for (final channel in _typedChannels.values) {
      futures.add(channel.close());
    }
    await Future.wait(futures);
    _typedChannels.clear();
    _activeTypedChannels = 0;
  }

  void _handleTypedListenerAttached() {
    _activeTypedChannels++;
  }

  void _handleTypedListenerDetached() {
    if (_activeTypedChannels == 0) {
      return;
    }
    _activeTypedChannels--;
  }
}

abstract interface class _TypedChannelBase {
  Stream<DrawEvent> get stream;
  bool get hasListeners;
  bool matches(DrawEvent event);
  bool acceptsType<T extends DrawEvent>();
  void emit(DrawEvent event);
  Future<void> close();
}

class _TypedChannel<T extends DrawEvent> implements _TypedChannelBase {
  _TypedChannel({
    required void Function() onFirstListener,
    required void Function() onLastListener,
  }) : _controller = StreamController<T>.broadcast(
         onListen: onFirstListener,
         onCancel: onLastListener,
       );

  final StreamController<T> _controller;

  @override
  Stream<T> get stream => _controller.stream;

  @override
  bool get hasListeners => _controller.hasListener;

  @override
  bool matches(DrawEvent event) => event is T;

  @override
  bool acceptsType<S extends DrawEvent>() => <S>[] is List<T>;

  @override
  void emit(DrawEvent event) {
    if (_controller.isClosed || !_controller.hasListener || event is! T) {
      return;
    }
    _controller.add(event);
  }

  @override
  Future<void> close() => _controller.close();
}
