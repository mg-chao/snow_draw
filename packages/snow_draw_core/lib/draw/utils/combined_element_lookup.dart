import '../models/element_state.dart';

/// A read-only view that combines a base element map with overlay updates.
///
/// This avoids creating a new map when we need to look up elements from
/// both the document and preview/updated elements. Lookups check the
/// overlay first, then fall back to the base map.
class CombinedElementLookup {
  const CombinedElementLookup({required this.base, this.overlay = const {}});

  /// The base element map (typically document.elementMap).
  final Map<String, ElementState> base;

  /// The overlay map (typically updated/preview elements).
  final Map<String, ElementState> overlay;

  /// Looks up an element by ID, checking overlay first.
  ElementState? operator [](String id) => overlay[id] ?? base[id];

  /// Returns true if the element exists in either map.
  bool containsKey(String id) =>
      overlay.containsKey(id) || base.containsKey(id);

  /// Returns all keys from both maps (overlay keys take precedence).
  Iterable<String> get keys sync* {
    yield* overlay.keys;
    for (final key in base.keys) {
      if (!overlay.containsKey(key)) {
        yield key;
      }
    }
  }

  /// Returns all values, with overlay values taking precedence.
  Iterable<ElementState> get values sync* {
    yield* overlay.values;
    for (final entry in base.entries) {
      if (!overlay.containsKey(entry.key)) {
        yield entry.value;
      }
    }
  }

  /// Creates a concrete map from this view.
  ///
  /// Use sparingly - prefer using the lookup directly when possible.
  Map<String, ElementState> toMap() => {...base, ...overlay};
}
