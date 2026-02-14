import 'dart:async';

import 'package:flutter/foundation.dart';

import '../actions/draw_actions.dart';
import '../config/draw_config.dart';
import '../core/draw_context.dart';
import '../events/event_bus.dart';
import '../input/plugin_system.dart';
import '../models/draw_state.dart';
import 'selector.dart';

typedef StateChangeListener<T> = void Function(T state);

enum DrawStateChange { document, selection, view, interaction }

/// DrawStore abstraction for testability.
///
/// Input-layer components should depend on this interface so tests can inject
/// lightweight fake implementations.
abstract interface class DrawStore implements StateProvider {
  DrawState get state;

  @override
  DrawState get currentState => state;

  DrawContext get context;
  DrawConfig get config;
  Stream<DrawConfig> get configStream;
  Stream<DrawEvent> get eventStream;

  /// Returns a typed event stream for [T].
  Stream<T> eventStreamOf<T extends DrawEvent>();

  /// Registers a typed event listener for [T].
  StreamSubscription<T> onEvent<T extends DrawEvent>(
    void Function(T event) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  });
  Future<void> call(DrawAction action);

  Future<void> dispatch(DrawAction action);

  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  });
  void unsubscribe(StateChangeListener<DrawState> listener);

  /// Subscribe to a specific state slice.
  ///
  /// Uses a selector to choose data from the full state.
  /// The listener is only called when the selected data changes.
  ///
  /// [selector] selects data from the state.
  /// [listener] is invoked when the selected data changes.
  /// [equals] optionally overrides equality; defaults to selector.equals.
  ///
  /// Returns a callback to unsubscribe.
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
  });
}
