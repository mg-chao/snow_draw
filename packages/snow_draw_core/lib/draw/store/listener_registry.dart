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
  var _filteredListenerCount = 0;

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

    final previousEntry = _listeners[listener];
    if (previousEntry != null && previousEntry.isFiltered) {
      _filteredListenerCount -= 1;
    }

    // Existing listeners keep their original order in the linked map.
    final entry = _ListenerEntry(listener, normalizedChangeTypes);
    _listeners[listener] = entry;

    if (entry.isFiltered) {
      _filteredListenerCount += 1;
    }

    return () => unregister(listener);
  }

  /// Unregister a listener.
  ///
  /// Removes the listener. O(1) removal with ordering preserved.
  void unregister(StateChangeListener<DrawState> listener) {
    final removed = _listeners.remove(listener);
    if (removed != null && removed.isFiltered) {
      _filteredListenerCount -= 1;
    }
  }

  /// Notify all listeners.
  ///
  /// Computes state changes and notifies listeners that care about them.
  /// Notifies listeners in registration order.
  void notify(DrawState previous, DrawState next) {
    if (_listeners.isEmpty) {
      return;
    }

    final documentChanged = previous.domain.document != next.domain.document;
    final selectionChanged = previous.domain.selection != next.domain.selection;
    final viewChanged = previous.application.view != next.application.view;
    final interactionChanged =
        previous.application.interaction != next.application.interaction;
    if (!documentChanged &&
        !selectionChanged &&
        !viewChanged &&
        !interactionChanged) {
      return;
    }

    // Fast path for the common case: no listeners use change filters.
    if (_filteredListenerCount == 0) {
      _notifyAllUnfiltered(next);
      return;
    }

    final changes = <DrawStateChange>{
      if (documentChanged) DrawStateChange.document,
      if (selectionChanged) DrawStateChange.selection,
      if (viewChanged) DrawStateChange.view,
      if (interactionChanged) DrawStateChange.interaction,
    };
    final context = StateChangeContext(
      previous: previous,
      next: next,
      changes: changes,
    );

    _notifyWithContext(context);
  }

  void _notifyAllUnfiltered(DrawState next) {
    // Notify listeners in registration order.
    // Use List.of() to avoid map mutation during notification.
    for (final listener in List.of(_listeners.keys)) {
      final entry = _listeners[listener];
      if (entry == null) {
        continue;
      }
      try {
        entry.notifyUnfiltered(next);
      } on Object catch (error, stackTrace) {
        // Continue notifying remaining listeners even when one throws.
        _onError?.call(error, stackTrace);
      }
    }
  }

  void _notifyWithContext(StateChangeContext context) {
    // Notify listeners in registration order.
    // Use List.of() to avoid map mutation during notification.
    for (final listener in List.of(_listeners.keys)) {
      final entry = _listeners[listener];
      if (entry == null) {
        continue;
      }
      try {
        entry.notify(context);
      } on Object catch (error, stackTrace) {
        // Continue notifying remaining listeners even when one throws.
        _onError?.call(error, stackTrace);
      }
    }
  }

  /// Clear all listeners.
  void clear() {
    _listeners.clear();
    _filteredListenerCount = 0;
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
    : _chain = StateChangeChain.forChanges(changeTypes),
      isFiltered = changeTypes != null && changeTypes.isNotEmpty;
  final StateChangeListener<DrawState> listener;
  final StateChangeChain _chain;
  final bool isFiltered;

  /// Notify an unfiltered listener.
  void notifyUnfiltered(DrawState state) => listener(state);

  /// Notify the listener.
  void notify(StateChangeContext context) => _chain.notify(context, listener);
}
