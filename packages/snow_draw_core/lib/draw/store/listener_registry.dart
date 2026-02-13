import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/draw_state.dart';
import 'draw_store_interface.dart';
import 'state_change_chain.dart';

/// Callback invoked when a listener throws during notification.
typedef ListenerErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Listener registry.
///
/// Manages registration, unregistration, and notification of state
/// listeners.
/// Supports fine-grained change type filtering to notify only relevant
/// listeners.
///
/// Uses a LinkedHashMap for O(1) removal, de-duplication, and ordered notify.
class ListenerRegistry {
  ListenerRegistry({ListenerErrorHandler? onError}) : _onError = onError;

  final ListenerErrorHandler? _onError;
  final LinkedHashMap<StateChangeListener<DrawState>, _ListenerEntry>
  _listeners = LinkedHashMap();

  /// Register a listener.
  ///
  /// Returns a callback to unregister.
  /// [changeTypes] optionally specifies which change types the listener cares
  /// about.
  ///
  /// If the listener is already registered, update its changeTypes
  /// (deduped).
  VoidCallback register(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    // If the listener already exists, update its config.
    if (_listeners.containsKey(listener)) {
      _listeners[listener] = _ListenerEntry(listener, changeTypes);
    } else {
      // New listener: add to the map (preserves insertion order).
      final entry = _ListenerEntry(listener, changeTypes);
      _listeners[listener] = entry;
    }

    return () => unregister(listener);
  }

  /// Unregister a listener.
  ///
  /// Removes the listener. O(1) removal with ordering preserved.
  void unregister(StateChangeListener<DrawState> listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners.
  ///
  /// Computes state changes and notifies listeners that care about them.
  /// Notifies listeners in registration order.
  void notify(DrawState previous, DrawState next) {
    if (_listeners.isEmpty) {
      return;
    }

    final changes = computeDrawStateChanges(previous, next);
    if (changes.isEmpty) {
      return;
    }

    final context = StateChangeContext(
      previous: previous,
      next: next,
      changes: changes,
    );

    // Notify listeners in registration order.
    // Use List.of() to avoid map mutation during notification.
    for (final listener in List.of(_listeners.keys)) {
      final entry = _listeners[listener];
      if (entry != null && entry.shouldNotify(changes)) {
        try {
          entry.notify(context);
        } on Object catch (error, stackTrace) {
          // Continue notifying remaining listeners even when one throws.
          _onError?.call(error, stackTrace);
        }
      }
    }
  }

  /// Clear all listeners.
  void clear() {
    _listeners.clear();
  }

  /// Get listener count.
  int get count => _listeners.length;

  /// Whether empty.
  bool get isEmpty => _listeners.isEmpty;

  /// Whether non-empty.
  bool get isNotEmpty => _listeners.isNotEmpty;
}

/// Listener entry.
///
/// Internal class that stores a listener and its filter criteria.
class _ListenerEntry {
  _ListenerEntry(this.listener, this.changeTypes)
    : _chain = changeTypes != null
          ? StateChangeChain.forChanges(changeTypes)
          : null;
  final StateChangeListener<DrawState> listener;
  final Set<DrawStateChange>? changeTypes;
  final StateChangeChain? _chain;

  /// Determine whether to notify this listener.
  ///
  /// If changeTypes is not specified, always notify.
  /// Otherwise, notify only if changes include the listener's interests.
  bool shouldNotify(Set<DrawStateChange> changes) {
    if (changeTypes == null) {
      return true;
    }
    return changes.any(changeTypes!.contains);
  }

  /// Notify the listener.
  ///
  /// Use StateChangeChain when available; otherwise call the listener directly.
  void notify(StateChangeContext context) {
    final chain = _chain;
    if (chain != null) {
      chain.notify(context, listener);
    } else {
      listener(context.next);
    }
  }
}
