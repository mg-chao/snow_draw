import 'dart:ui';

import '../../draw/config/draw_config.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import 'highlight_mask_painter.dart';

/// Signature for rendering a highlight-mask scene into a target [Canvas].
typedef HighlightMaskSceneRenderer =
    void Function({
      required Canvas canvas,
      required List<ElementState> highlights,
      required DrawRect viewportRect,
      required HighlightMaskConfig maskConfig,
      required double scaleFactor,
      required Offset cameraPosition,
    });

/// Caches the static highlight-mask overlay during interaction frames.
///
/// While creating or editing highlights, only a small subset of highlights
/// changes per frame. This cache records a picture for the static subset and
/// reuses it across frames so the dynamic painter only recomputes moving
/// highlight holes.
class HighlightMaskStaticSceneCache {
  HighlightMaskStaticSceneCache({HighlightMaskSceneRenderer? renderMask})
    : _renderMask = renderMask ?? paintHighlightMask;

  final HighlightMaskSceneRenderer _renderMask;
  _CachedStaticMaskScene? _cached;

  /// Paints the cached static highlight-mask scene when available.
  ///
  /// Returns `true` when a static scene was painted, `false` when
  /// [staticHighlights] is empty.
  bool paint({
    required Canvas canvas,
    required DocumentState document,
    required List<ElementState> staticHighlights,
    required Set<String> excludedDocumentHighlightIds,
    required DrawRect viewportRect,
    required HighlightMaskConfig maskConfig,
    required double scaleFactor,
    required Offset cameraPosition,
  }) {
    if (staticHighlights.isEmpty || maskConfig.maskOpacity <= 0) {
      return false;
    }

    final key = _StaticMaskSceneKey(
      document: document,
      excludedDocumentHighlightIds: Set<String>.unmodifiable(
        excludedDocumentHighlightIds,
      ),
      viewportRect: viewportRect,
      maskConfig: maskConfig,
      scaleKey: _quantize(scaleFactor),
      cameraXKey: _quantize(cameraPosition.dx),
      cameraYKey: _quantize(cameraPosition.dy),
    );

    final cached = _cached;
    if (cached == null || !cached.key.matches(key)) {
      cached?.picture.dispose();
      _cached = _CachedStaticMaskScene(
        key: key,
        picture: _recordStaticMaskScene(
          staticHighlights: staticHighlights,
          viewportRect: viewportRect,
          maskConfig: maskConfig,
          scaleFactor: scaleFactor,
          cameraPosition: cameraPosition,
        ),
      );
    }

    canvas.drawPicture(_cached!.picture);
    return true;
  }

  /// Clears cached picture resources.
  void clear() {
    _cached?.picture.dispose();
    _cached = null;
  }

  Picture _recordStaticMaskScene({
    required List<ElementState> staticHighlights,
    required DrawRect viewportRect,
    required HighlightMaskConfig maskConfig,
    required double scaleFactor,
    required Offset cameraPosition,
  }) {
    final recorder = PictureRecorder();
    final sceneCanvas = Canvas(recorder);
    _renderMask(
      canvas: sceneCanvas,
      highlights: staticHighlights,
      viewportRect: viewportRect,
      maskConfig: maskConfig,
      scaleFactor: scaleFactor,
      cameraPosition: cameraPosition,
    );
    return recorder.endRecording();
  }

  int _quantize(double value) => (value * 1000).round();
}

class _CachedStaticMaskScene {
  const _CachedStaticMaskScene({required this.key, required this.picture});

  final _StaticMaskSceneKey key;
  final Picture picture;
}

class _StaticMaskSceneKey {
  const _StaticMaskSceneKey({
    required this.document,
    required this.excludedDocumentHighlightIds,
    required this.viewportRect,
    required this.maskConfig,
    required this.scaleKey,
    required this.cameraXKey,
    required this.cameraYKey,
  });

  final DocumentState document;
  final Set<String> excludedDocumentHighlightIds;
  final DrawRect viewportRect;
  final HighlightMaskConfig maskConfig;
  final int scaleKey;
  final int cameraXKey;
  final int cameraYKey;

  bool matches(_StaticMaskSceneKey other) =>
      identical(document, other.document) &&
      viewportRect == other.viewportRect &&
      maskConfig == other.maskConfig &&
      scaleKey == other.scaleKey &&
      cameraXKey == other.cameraXKey &&
      cameraYKey == other.cameraYKey &&
      _setEquals(
        excludedDocumentHighlightIds,
        other.excludedDocumentHighlightIds,
      );

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }
}
