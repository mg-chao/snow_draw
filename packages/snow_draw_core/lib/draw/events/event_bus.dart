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
  final _controller = StreamController<DrawEvent>.broadcast();

  /// Event stream.
  Stream<DrawEvent> get stream => _controller.stream;

  /// Emit an event.
  void emit(DrawEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Subscribe to a specific event type.
  StreamSubscription<T> on<T extends DrawEvent>(
    void Function(T event) handler,
  ) => stream.where((e) => e is T).cast<T>().listen(handler);

  /// Close the event bus.
  Future<void> dispose() => _controller.close();
}
