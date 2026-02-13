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
  /// Passing `null` or an empty set listens to all state changes.
  ///
  /// If the listener is already registered, update its changeTypes
  /// (deduped).
  VoidCallback register(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    final normalizedChangeTypes = _normalizeChangeTypes(changeTypes);

    // Existing listeners keep their original order in the linked map.
    _listeners[listener] = _ListenerEntry(listener, normalizedChangeTypes);

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
      if (entry != null) {
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

  Set<DrawStateChange>? _normalizeChangeTypes(Set<DrawStateChange>? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return Set<DrawStateChange>.unmodifiable(Set<DrawStateChange>.of(value));
  }
}

/// Listener entry.
///
/// Internal class that stores a listener and its prebuilt notify chain.
class _ListenerEntry {
  _ListenerEntry(this.listener, Set<DrawStateChange>? changeTypes)
    : _chain = StateChangeChain.forChanges(changeTypes);
  final StateChangeListener<DrawState> listener;
  final StateChangeChain _chain;

  /// Notify the listener.
  void notify(StateChangeContext context) => _chain.notify(context, listener);
}
