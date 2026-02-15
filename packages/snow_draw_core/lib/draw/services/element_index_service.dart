import '../models/element_state.dart';

/// Computes and caches element lookup indexes for a specific element list.
///
/// This is intended to be a short-lived object: create a new instance whenever
/// the underlying element list changes.
class ElementIndexService {
  ElementIndexService(List<ElementState> elements)
    : _elements = List<ElementState>.unmodifiable(elements);
  final List<ElementState> _elements;

  Map<String, ElementState>? _byIdCache;

  Map<String, ElementState> get byId {
    final cached = _byIdCache;
    if (cached != null) {
      return cached;
    }
    final map = <String, ElementState>{};
    for (final element in _elements) {
      map[element.id] = element;
    }
    final unmodifiable = Map<String, ElementState>.unmodifiable(map);
    _byIdCache = unmodifiable;
    return unmodifiable;
  }

  ElementState? operator [](String id) => byId[id];

  bool containsId(String id) => byId.containsKey(id);
}
