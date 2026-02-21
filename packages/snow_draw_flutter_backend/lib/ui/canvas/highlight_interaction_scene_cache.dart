import 'dart:ui';

import 'package:meta/meta.dart';

import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

/// Callback used to draw a single element into a target [Canvas].
typedef SceneElementPainter =
    void Function(Canvas canvas, ElementState element);

/// Caches static scene segments during high-frequency interactions.
///
/// Interactive create/edit flows only mutate a small subset of elements while
/// most of the visible scene stays unchanged. This cache records stable
/// segments into [Picture] objects and replays them across frames so only
/// dynamic elements are repainted.
class InteractionSceneCache {
  InteractionSceneCache({int maxEntries = 24})
    : _segmentCache = LruCache<int, _CachedSegment>(
        maxEntries: maxEntries,
        onEvict: (entry) => entry.picture.dispose(),
      );

  final LruCache<int, _CachedSegment> _segmentCache;
  _SegmentLayoutCacheEntry? _layoutCacheEntry;

  @visibleForTesting
  int get debugEntryCount => _segmentCache.length;

  /// Clears all cached segments and disposes the underlying pictures.
  void clear() {
    _segmentCache.clear();
    _layoutCacheEntry = null;
  }

  /// Paints [elements] in z-order, reusing cached pictures for static ranges.
  ///
  /// [dynamicElementIds] identifies elements that can change every frame
  /// (typically preview highlights). Those elements are always repainted.
  void paint({
    required Canvas canvas,
    required List<ElementState> elements,
    required Set<String> dynamicElementIds,
    required int documentVersion,
    required int textRenderingCacheRevision,
    required double scaleFactor,
    required Locale? locale,
    required SceneElementPainter paintElement,
  }) {
    if (elements.isEmpty) {
      return;
    }

    final layout = _resolveSegmentLayout(
      elements: elements,
      dynamicElementIds: dynamicElementIds,
    );
    final localeTag = locale?.toLanguageTag() ?? '';
    final scaleKey = _quantizeScale(scaleFactor);
    for (var i = 0; i < layout.dynamicIndices.length; i++) {
      final staticRange = layout.staticRanges[i];
      _drawStaticSegment(
        canvas: canvas,
        elements: elements,
        staticRange: staticRange,
        documentVersion: documentVersion,
        textRenderingCacheRevision: textRenderingCacheRevision,
        scaleKey: scaleKey,
        localeTag: localeTag,
        paintElement: paintElement,
      );
      final dynamicIndex = layout.dynamicIndices[i];
      paintElement(canvas, elements[dynamicIndex]);
    }

    _drawStaticSegment(
      canvas: canvas,
      elements: elements,
      staticRange: layout.staticRanges.last,
      documentVersion: documentVersion,
      textRenderingCacheRevision: textRenderingCacheRevision,
      scaleKey: scaleKey,
      localeTag: localeTag,
      paintElement: paintElement,
    );
  }

  void _drawStaticSegment({
    required Canvas canvas,
    required List<ElementState> elements,
    required _StaticSegmentRange staticRange,
    required int documentVersion,
    required int textRenderingCacheRevision,
    required int scaleKey,
    required String localeTag,
    required SceneElementPainter paintElement,
  }) {
    final start = staticRange.start;
    final end = staticRange.end;
    if (start >= end) {
      return;
    }

    final fingerprint = staticRange.fingerprint;
    final cached = _segmentCache.get(fingerprint);
    if (cached != null &&
        cached.matches(
          elements: elements,
          start: start,
          end: end,
          documentVersion: documentVersion,
          textRenderingCacheRevision: textRenderingCacheRevision,
          scaleKey: scaleKey,
          localeTag: localeTag,
        )) {
      canvas.drawPicture(cached.picture);
      return;
    }

    final picture = _recordSegment(
      elements: elements,
      start: start,
      end: end,
      paintElement: paintElement,
    );

    final nextEntry = _CachedSegment(
      picture: picture,
      elementRefs: [
        for (var index = start; index < end; index++) elements[index],
      ],
      documentVersion: documentVersion,
      textRenderingCacheRevision: textRenderingCacheRevision,
      scaleKey: scaleKey,
      localeTag: localeTag,
    );
    _segmentCache.put(fingerprint, nextEntry);
    canvas.drawPicture(picture);
  }

  _SegmentLayout _resolveSegmentLayout({
    required List<ElementState> elements,
    required Set<String> dynamicElementIds,
  }) {
    final cached = _layoutCacheEntry;
    if (cached != null &&
        cached.matches(
          elements: elements,
          dynamicElementIds: dynamicElementIds,
        )) {
      return cached.layout;
    }

    final dynamicIndices = <int>[];
    final staticRanges = <_StaticSegmentRange>[];
    var segmentStart = 0;

    for (var index = 0; index < elements.length; index++) {
      if (!dynamicElementIds.contains(elements[index].id)) {
        continue;
      }
      staticRanges.add(
        _StaticSegmentRange(
          start: segmentStart,
          end: index,
          fingerprint: _segmentFingerprint(elements, segmentStart, index),
        ),
      );
      dynamicIndices.add(index);
      segmentStart = index + 1;
    }

    staticRanges.add(
      _StaticSegmentRange(
        start: segmentStart,
        end: elements.length,
        fingerprint: _segmentFingerprint(
          elements,
          segmentStart,
          elements.length,
        ),
      ),
    );

    final layout = _SegmentLayout(
      dynamicIndices: List<int>.unmodifiable(dynamicIndices),
      staticRanges: List<_StaticSegmentRange>.unmodifiable(staticRanges),
    );
    _layoutCacheEntry = _SegmentLayoutCacheEntry(
      elements: elements,
      dynamicElementIds: Set<String>.unmodifiable(dynamicElementIds),
      layout: layout,
    );
    return layout;
  }

  Picture _recordSegment({
    required List<ElementState> elements,
    required int start,
    required int end,
    required SceneElementPainter paintElement,
  }) {
    final recorder = PictureRecorder();
    final segmentCanvas = Canvas(recorder);
    for (var index = start; index < end; index++) {
      paintElement(segmentCanvas, elements[index]);
    }
    return recorder.endRecording();
  }

  int _segmentFingerprint(List<ElementState> elements, int start, int end) {
    var hash = 17;
    for (var index = start; index < end; index++) {
      hash = 0x1fffffff & (hash * 31 + elements[index].id.hashCode);
    }
    return 0x1fffffff & (hash * 31 + (end - start));
  }

  int _quantizeScale(double scaleFactor) => (scaleFactor * 1000).round();
}

/// Backward-compatible alias.
typedef HighlightSceneElementPainter = SceneElementPainter;

/// Backward-compatible alias.
class HighlightInteractionSceneCache extends InteractionSceneCache {
  HighlightInteractionSceneCache({super.maxEntries = 24});
}

@immutable
class _CachedSegment {
  const _CachedSegment({
    required this.picture,
    required this.elementRefs,
    required this.documentVersion,
    required this.textRenderingCacheRevision,
    required this.scaleKey,
    required this.localeTag,
  });

  final Picture picture;
  final List<ElementState> elementRefs;
  final int documentVersion;
  final int textRenderingCacheRevision;
  final int scaleKey;
  final String localeTag;

  bool matches({
    required List<ElementState> elements,
    required int start,
    required int end,
    required int documentVersion,
    required int textRenderingCacheRevision,
    required int scaleKey,
    required String localeTag,
  }) {
    if (this.documentVersion != documentVersion ||
        this.textRenderingCacheRevision != textRenderingCacheRevision ||
        this.scaleKey != scaleKey ||
        this.localeTag != localeTag) {
      return false;
    }

    final length = end - start;
    if (elementRefs.length != length) {
      return false;
    }

    for (var index = 0; index < length; index++) {
      if (!identical(elementRefs[index], elements[start + index])) {
        return false;
      }
    }

    return true;
  }
}

class _StaticSegmentRange {
  const _StaticSegmentRange({
    required this.start,
    required this.end,
    required this.fingerprint,
  });

  final int start;
  final int end;
  final int fingerprint;
}

class _SegmentLayout {
  const _SegmentLayout({
    required this.dynamicIndices,
    required this.staticRanges,
  });

  final List<int> dynamicIndices;
  final List<_StaticSegmentRange> staticRanges;
}

class _SegmentLayoutCacheEntry {
  const _SegmentLayoutCacheEntry({
    required this.elements,
    required this.dynamicElementIds,
    required this.layout,
  });

  final List<ElementState> elements;
  final Set<String> dynamicElementIds;
  final _SegmentLayout layout;

  bool matches({
    required List<ElementState> elements,
    required Set<String> dynamicElementIds,
  }) =>
      identical(this.elements, elements) &&
      this.dynamicElementIds.length == dynamicElementIds.length &&
      this.dynamicElementIds.containsAll(dynamicElementIds);
}
