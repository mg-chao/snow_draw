import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../draw/input/input_event.dart';

typedef PointerMoveEventSink =
    Future<void> Function(PointerMoveInputEvent event);

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
  }) : _dispatchMove = dispatchMove,
       _shouldCoalesce = shouldCoalesce;

  final PointerMoveEventSink _dispatchMove;
  final bool Function() _shouldCoalesce;

  PointerMoveInputEvent? _pendingMove;
  Future<void>? _inFlightDispatch;
  var _withoutCoalescingQueue = Future<void>.value();
  var _frameCallbackScheduled = false;
  var _isDisposed = false;

  void dispatch(PointerMoveInputEvent event) {
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

    _pendingMove = event;
    _scheduleFrameDispatch();
  }

  Future<void> flush() async {
    if (_isDisposed) {
      return;
    }
    await _withoutCoalescingQueue;
    await _waitForInFlightDispatch();
    final pending = _takePendingMove();
    if (pending == null) {
      return;
    }
    await _dispatchImmediately(pending);
  }

  void reset() {
    _pendingMove = null;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _pendingMove = null;
    await _withoutCoalescingQueue;
    await _waitForInFlightDispatch();
  }

  Future<void> _dispatchWithoutCoalescing(PointerMoveInputEvent event) async {
    await _waitForInFlightDispatch();
    final pending = _takePendingMove();
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
    final pending = _takePendingMove();
    if (pending == null) {
      return;
    }
    await _dispatchImmediately(pending);
    if (_pendingMove != null) {
      if (_shouldCoalesce()) {
        _scheduleFrameDispatch();
      } else {
        final remaining = _takePendingMove();
        if (remaining != null) {
          await _dispatchImmediately(remaining);
        }
      }
    }
  }

  Future<void> _dispatchImmediately(PointerMoveInputEvent event) {
    final future = _dispatchMove(event);
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

  PointerMoveInputEvent? _takePendingMove() {
    final pending = _pendingMove;
    _pendingMove = null;
    return pending;
  }
}
