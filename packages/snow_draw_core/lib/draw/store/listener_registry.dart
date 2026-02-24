import 'dart:collection';

import '../core/callbacks.dart';
import '../models/draw_state.dart';
import '../models/interaction_state.dart';
import 'draw_store_interface.dart';

/// Callback invoked when a listener throws during notification.
typedef ListenerErrorHandler =
    void Function(Object error, StackTrace stackTrace);

const int _documentChangeMask = 1 << 0;
const int _selectionChangeMask = 1 << 1;
const int _viewChangeMask = 1 << 2;
const int _interactionChangeMask = 1 << 3;
const int _allChangeMask =
    _documentChangeMask |
    _selectionChangeMask |
    _viewChangeMask |
    _interactionChangeMask;

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
    final normalizedChangeMask = _normalizeChangeMask(changeTypes);

    // Existing listeners keep their original order in the linked map.
    final entry = _ListenerEntry(listener, normalizedChangeMask);
    _listeners[listener] = entry;

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

    final entriesSnapshot = List<_ListenerEntry>.of(_listeners.values);
    final hasFilteredListeners = entriesSnapshot.any(
      (entry) => entry.isFiltered,
    );

    // Fast path for the common case: no listeners use change filters.
    if (!hasFilteredListeners) {
      if (!_hasTrackedChanges(previous, next)) {
        return;
      }
      _notifyEntries(entriesSnapshot, next);
      return;
    }

    final changeMask = _computeChangeMask(previous, next);
    if (changeMask == 0) {
      return;
    }
    _notifyEntries(entriesSnapshot, next, changeMask: changeMask);
  }

  void _notifyEntries(
    List<_ListenerEntry> entries,
    DrawState next, {
    int? changeMask,
  }) {
    for (final entry in entries) {
      if (!_isCurrentEntry(entry)) {
        continue;
      }
      if (changeMask != null && !entry.matches(changeMask)) {
        continue;
      }
      try {
        entry.listener(next);
      } on Object catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
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

  bool _isCurrentEntry(_ListenerEntry entry) =>
      identical(_listeners[entry.listener], entry);

  int? _normalizeChangeMask(Set<DrawStateChange>? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    var mask = 0;
    for (final change in value) {
      mask |= _maskForChange(change);
    }

    if (mask == _allChangeMask) {
      return null;
    }

    return mask;
  }
}

/// Listener entry.
///
/// Internal class that stores a listener and its normalized change mask.
class _ListenerEntry {
  _ListenerEntry(this.listener, this.changeMask);
  final StateChangeListener<DrawState> listener;
  final int? changeMask;
  bool get isFiltered => changeMask != null;

  /// Returns true when this listener should receive the current change mask.
  bool matches(int stateChangeMask) {
    final mask = changeMask;
    return mask == null || (mask & stateChangeMask) != 0;
  }
}

int _computeChangeMask(DrawState previous, DrawState next) {
  var mask = 0;

  if (_documentChanged(previous, next)) {
    mask |= _documentChangeMask;
  }
  if (_selectionChanged(previous, next)) {
    mask |= _selectionChangeMask;
  }
  if (_viewChanged(previous, next)) {
    mask |= _viewChangeMask;
  }
  if (_interactionChanged(previous, next)) {
    mask |= _interactionChangeMask;
  }

  return mask;
}

bool _hasTrackedChanges(DrawState previous, DrawState next) =>
    _documentChanged(previous, next) ||
    _selectionChanged(previous, next) ||
    _viewChanged(previous, next) ||
    _interactionChanged(previous, next);

bool _documentChanged(DrawState previous, DrawState next) {
  final previousDocument = previous.domain.document;
  final nextDocument = next.domain.document;
  if (identical(previousDocument, nextDocument)) {
    return false;
  }
  if (previousDocument.elementsVersion != nextDocument.elementsVersion) {
    return true;
  }
  return previousDocument != nextDocument;
}

bool _selectionChanged(DrawState previous, DrawState next) {
  final previousSelection = previous.domain.selection;
  final nextSelection = next.domain.selection;
  if (identical(previousSelection, nextSelection)) {
    return false;
  }
  if (previousSelection.selectionVersion != nextSelection.selectionVersion) {
    return true;
  }
  return previousSelection != nextSelection;
}

bool _viewChanged(DrawState previous, DrawState next) {
  final previousView = previous.application.view;
  final nextView = next.application.view;
  return !identical(previousView, nextView) && previousView != nextView;
}

bool _interactionChanged(DrawState previous, DrawState next) {
  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  if (identical(previousInteraction, nextInteraction)) {
    return false;
  }

  if (previousInteraction is TextEditingState &&
      nextInteraction is TextEditingState) {
    return _textEditingChanged(previousInteraction, nextInteraction);
  }

  return previousInteraction != nextInteraction;
}

bool _textEditingChanged(TextEditingState previous, TextEditingState next) =>
    previous.elementId != next.elementId ||
    previous.isNew != next.isNew ||
    previous.opacity != next.opacity ||
    previous.rotation != next.rotation ||
    previous.initialCursorPosition != next.initialCursorPosition ||
    !identical(previous.draftData, next.draftData) ||
    previous.rect != next.rect;

int _maskForChange(DrawStateChange change) => switch (change) {
  DrawStateChange.document => _documentChangeMask,
  DrawStateChange.selection => _selectionChangeMask,
  DrawStateChange.view => _viewChangeMask,
  DrawStateChange.interaction => _interactionChangeMask,
};
