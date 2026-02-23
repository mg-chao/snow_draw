import 'package:snow_draw_core/snow_draw_core.dart';
import 'visible_element_resolver.dart';

/// Caches the latest base visible scene query for scene-painter frames.
///
/// Highlight/filter edit flows can invalidate interaction previews every frame
/// while document geometry and viewport stay unchanged. Reusing the latest
/// viewport query avoids repeating spatial-index range queries on every frame.
class VisibleElementSceneCache {
  _VisibleElementSceneCacheEntry? _entry;

  /// Resolves the base visible scene, reusing the last cached query when
  /// document identity and viewport constraints are unchanged.
  List<ElementState> resolve({
    required DocumentState document,
    required DrawRect viewportRect,
    int? minOrderIndex,
    int? maxOrderIndex,
  }) {
    final cached = _entry;
    if (cached != null &&
        identical(cached.document, document) &&
        cached.viewportRect == viewportRect &&
        cached.minOrderIndex == minOrderIndex &&
        cached.maxOrderIndex == maxOrderIndex) {
      return cached.elements;
    }

    final resolved = List<ElementState>.unmodifiable(
      resolveBaseVisibleElementScene(
        document: document,
        viewportRect: viewportRect,
        minOrderIndex: minOrderIndex,
        maxOrderIndex: maxOrderIndex,
      ),
    );
    _entry = _VisibleElementSceneCacheEntry(
      document: document,
      viewportRect: viewportRect,
      minOrderIndex: minOrderIndex,
      maxOrderIndex: maxOrderIndex,
      elements: resolved,
    );
    return resolved;
  }

  /// Clears the cached scene query.
  void clear() => _entry = null;
}

class _VisibleElementSceneCacheEntry {
  const _VisibleElementSceneCacheEntry({
    required this.document,
    required this.viewportRect,
    required this.minOrderIndex,
    required this.maxOrderIndex,
    required this.elements,
  });

  final DocumentState document;
  final DrawRect viewportRect;
  final int? minOrderIndex;
  final int? maxOrderIndex;
  final List<ElementState> elements;
}
