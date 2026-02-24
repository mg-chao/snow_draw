import 'dart:collection';

import '../core/callbacks.dart';
import '../models/draw_state.dart';
import '../models/interaction_state.dart';
import 'draw_store_interface.dart';

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
  /// Passing `null` or an empty set listens to all tracked state changes.
  ///
  /// If the listener is already registered, update its changeTypes
  /// (deduped).
  VoidCallback register(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    final normalizedChangeTypes = _normalizeChangeTypes(changeTypes);

    // Existing listeners keep their original order in the linked map.
    final entry = _ListenerEntry(listener, normalizedChangeTypes);
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
    final stateChanges = _computeChanges(previous, next);
    if (stateChanges.isEmpty) {
      return;
    }
    _notifyEntries(entriesSnapshot, next, stateChanges: stateChanges);
  }

  void _notifyEntries(
    List<_ListenerEntry> entries,
    DrawState next, {
    required Set<DrawStateChange> stateChanges,
  }) {
    for (final entry in entries) {
      if (!_isCurrentEntry(entry)) {
        continue;
      }
      if (!entry.matches(stateChanges)) {
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

  Set<DrawStateChange>? _normalizeChangeTypes(Set<DrawStateChange>? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return Set<DrawStateChange>.unmodifiable(value);
  }
}

/// Listener entry.
///
/// Internal class that stores a listener and its normalized change mask.
class _ListenerEntry {
  _ListenerEntry(this.listener, this.changeTypes);
  final StateChangeListener<DrawState> listener;
  final Set<DrawStateChange>? changeTypes;

  /// Returns true when this listener should receive the current changes.
  bool matches(Set<DrawStateChange> stateChanges) {
    final interested = changeTypes;
    if (interested == null) {
      return true;
    }
    for (final change in stateChanges) {
      if (interested.contains(change)) {
        return true;
      }
    }
    return false;
  }
}

Set<DrawStateChange> _computeChanges(DrawState previous, DrawState next) {
  final changes = <DrawStateChange>{};

  if (_documentChanged(previous, next)) {
    changes.add(DrawStateChange.document);
  }
  if (_selectionChanged(previous, next)) {
    changes.add(DrawStateChange.selection);
  }
  if (_viewChanged(previous, next)) {
    changes.add(DrawStateChange.view);
  }
  if (_interactionChanged(previous, next)) {
    changes.add(DrawStateChange.interaction);
  }

  return changes;
}

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
