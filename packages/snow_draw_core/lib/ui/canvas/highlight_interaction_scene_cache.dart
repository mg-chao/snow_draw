import 'dart:ui';

import 'package:meta/meta.dart';

import '../../draw/models/element_state.dart';
import '../../draw/utils/lru_cache.dart';

/// Callback used to draw a single element into a target [Canvas].
typedef HighlightSceneElementPainter =
    void Function(Canvas canvas, ElementState element);

/// Caches static scene segments during high-frequency highlight interactions.
///
/// Highlight create/edit flows only mutate a small subset of elements while
/// most of the visible scene stays unchanged. This cache records stable
/// segments into [Picture] objects and replays them across frames so only
/// dynamic elements are repainted.
class HighlightInteractionSceneCache {
  HighlightInteractionSceneCache({int maxEntries = 24})
    : _segmentCache = LruCache<int, _CachedSegment>(
        maxEntries: maxEntries,
        onEvict: (entry) => entry.picture.dispose(),
      );

  final LruCache<int, _CachedSegment> _segmentCache;

  @visibleForTesting
  int get debugEntryCount => _segmentCache.length;

  /// Clears all cached segments and disposes the underlying pictures.
  void clear() {
    _segmentCache.clear();
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
    required HighlightSceneElementPainter paintElement,
  }) {
    if (elements.isEmpty) {
      return;
    }

    final localeTag = locale?.toLanguageTag() ?? '';
    final scaleKey = _quantizeScale(scaleFactor);

    var segmentStart = 0;
    for (var index = 0; index < elements.length; index++) {
      final element = elements[index];
      if (!dynamicElementIds.contains(element.id)) {
        continue;
      }

      _drawStaticSegment(
        canvas: canvas,
        elements: elements,
        start: segmentStart,
        end: index,
        documentVersion: documentVersion,
        textRenderingCacheRevision: textRenderingCacheRevision,
        scaleKey: scaleKey,
        localeTag: localeTag,
        paintElement: paintElement,
      );
      paintElement(canvas, element);
      segmentStart = index + 1;
    }

    _drawStaticSegment(
      canvas: canvas,
      elements: elements,
      start: segmentStart,
      end: elements.length,
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
    required int start,
    required int end,
    required int documentVersion,
    required int textRenderingCacheRevision,
    required int scaleKey,
    required String localeTag,
    required HighlightSceneElementPainter paintElement,
  }) {
    if (start >= end) {
      return;
    }

    final fingerprint = _segmentFingerprint(elements, start, end);
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

  Picture _recordSegment({
    required List<ElementState> elements,
    required int start,
    required int end,
    required HighlightSceneElementPainter paintElement,
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

  int _quantizeScale(double scaleFactor) {
    final normalized = scaleFactor == 0 ? 1.0 : scaleFactor;
    return (normalized * 1000).round();
  }
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
