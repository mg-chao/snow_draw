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
  final Map<Type, Stream<DrawEvent>> _typedStreams = {};
  Future<void>? _disposeFuture;

  /// Event stream.
  Stream<DrawEvent> get stream => _controller.stream;

  /// Whether there are active listeners.
  bool get hasListeners => _controller.hasListener;

  /// Whether the event bus has been disposed.
  bool get isDisposed => _controller.isClosed;

  /// Emit an event.
  void emit(DrawEvent event) {
    if (_controller.isClosed || !_controller.hasListener) {
      return;
    }
    _controller.add(event);
  }

  /// Typed stream for a specific event type.
  Stream<T> streamOf<T extends DrawEvent>() {
    final cached = _typedStreams[T];
    if (cached != null) {
      return cached as Stream<T>;
    }

    final typed = stream.where((event) => event is T).cast<T>();
    _typedStreams[T] = typed;
    return typed;
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

    _typedStreams.clear();
    final closing = _controller.close();
    _disposeFuture = closing;
    return closing;
  }
}
