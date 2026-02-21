import '../models/element_state.dart';

/// Computes and caches element lookup indexes for a specific element list.
///
/// This is intended to be a short-lived object: create a new instance whenever
/// the underlying element list changes.
class ElementIndexService {
  ElementIndexService(List<ElementState> elements)
    : byId = Map<String, ElementState>.unmodifiable(<String, ElementState>{
        for (final element in elements) element.id: element,
      });

  final Map<String, ElementState> byId;

  ElementState? operator [](String id) => byId[id];

  bool containsId(String id) => byId.containsKey(id);
}
