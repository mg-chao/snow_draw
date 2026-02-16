import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../draw/input/input_event.dart';

typedef PointerMoveEventSink =
    Future<void> Function(PointerMoveInputEvent event);

typedef FrameAlignedEventSink<T> = Future<void> Function(T event);

/// Dispatches high-frequency events with optional frame-aligned coalescing.
///
/// Callers can coalesce to the latest event per frame for interaction paths
/// where only the latest position matters, while keeping other flows fully
/// unthrottled.
class FrameAlignedEventDispatcher<T> {
  FrameAlignedEventDispatcher({
    required FrameAlignedEventSink<T> dispatchEvent,
    required bool Function() shouldCoalesce,
  }) : _dispatchEvent = _eraseDispatch(dispatchEvent),
       _shouldCoalesce = shouldCoalesce;

  final Future<void> Function(Object?) _dispatchEvent;
  final bool Function() _shouldCoalesce;

  T? _pendingEvent;
  Future<void>? _inFlightDispatch;
  var _withoutCoalescingQueue = Future<void>.value();
  var _frameCallbackScheduled = false;
  var _isDisposed = false;

  void dispatch(T event) {
    if (_isDisposed) {
      return;
    }

    if (!_shouldCoalesce()) {
      final queued = _withoutCoalescingQueue.then(
        (_) => _dispatchWithoutCoalescing(event),
      );
      _withoutCoalescingQueue = queued.catchError((Object _) {});
      unawaited(queued);
      return;
    }

    _pendingEvent = event;
    _scheduleFrameDispatch();
  }

  Future<void> flush() async {
    if (_isDisposed) {
      return;
    }
    await _withoutCoalescingQueue;
    await _waitForInFlightDispatch();
    final pending = _takePendingEvent();
    if (pending == null) {
      return;
    }
    await _dispatchImmediately(pending);
  }

  void reset() {
    _pendingEvent = null;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _pendingEvent = null;
    await _withoutCoalescingQueue;
    await _waitForInFlightDispatch();
  }

  Future<void> _dispatchWithoutCoalescing(T event) async {
    await _waitForInFlightDispatch();
    final pending = _takePendingEvent();
    if (pending != null) {
      await _dispatchImmediately(pending);
    }
    await _dispatchImmediately(event);
  }

  void _scheduleFrameDispatch() {
    if (_frameCallbackScheduled || _isDisposed) {
      return;
    }
    _frameCallbackScheduled = true;
    SchedulerBinding.instance
      ..scheduleFrameCallback((_) {
        _frameCallbackScheduled = false;
        unawaited(_drainPendingOnFrame());
      })
      ..ensureVisualUpdate();
  }

  Future<void> _drainPendingOnFrame() async {
    if (_isDisposed) {
      return;
    }
    await _waitForInFlightDispatch();
    final pending = _takePendingEvent();
    if (pending == null) {
      return;
    }
    await _dispatchImmediately(pending);
    if (_pendingEvent != null) {
      if (_shouldCoalesce()) {
        _scheduleFrameDispatch();
      } else {
        final remaining = _takePendingEvent();
        if (remaining != null) {
          await _dispatchImmediately(remaining);
        }
      }
    }
  }

  Future<void> _dispatchImmediately(T event) {
    final future = _dispatchEvent(event);
    _inFlightDispatch = future;
    return future.whenComplete(() {
      if (identical(_inFlightDispatch, future)) {
        _inFlightDispatch = null;
      }
    });
  }

  Future<void> _waitForInFlightDispatch() async {
    final inFlight = _inFlightDispatch;
    if (inFlight != null) {
      await inFlight;
    }
  }

  T? _takePendingEvent() {
    final pending = _pendingEvent;
    _pendingEvent = null;
    return pending;
  }

  static Future<void> Function(Object?) _eraseDispatch<T>(
    FrameAlignedEventSink<T> dispatchEvent,
  ) =>
      (event) => dispatchEvent(event as T);
}

/// Dispatches pointer move events with optional frame-aligned coalescing.
///
/// Interactive transforms (move/resize/create) only need the latest pointer
/// position per frame to render smoothly. This dispatcher keeps free-draw-like
/// tools fully unthrottled while coalescing rectangle-style interactions to one
/// update per frame.
class FrameAlignedPointerMoveDispatcher {
  FrameAlignedPointerMoveDispatcher({
    required PointerMoveEventSink dispatchMove,
    required bool Function() shouldCoalesce,
  }) : _dispatcher = FrameAlignedEventDispatcher<PointerMoveInputEvent>(
         dispatchEvent: dispatchMove,
         shouldCoalesce: shouldCoalesce,
       );

  final FrameAlignedEventDispatcher<PointerMoveInputEvent> _dispatcher;

  void dispatch(PointerMoveInputEvent event) {
    _dispatcher.dispatch(event);
  }

  Future<void> flush() => _dispatcher.flush();

  void reset() => _dispatcher.reset();

  Future<void> dispose() => _dispatcher.dispose();
}
