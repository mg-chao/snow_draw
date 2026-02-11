import 'dart:math' as math;
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import 'free_draw_data.dart';
import 'free_draw_path_utils.dart';

/// Cached visual data for a single free-draw element.
///
/// Holds the smooth center-line path and derived stroke paths so
/// that both the renderer and hit tester can share the same
/// computation. The flattened points are lazily built on first
/// hit-test request and then reused.
///
/// For completed (non-creating) strokes, a `Picture` is recorded
/// on first render and replayed on subsequent frames, turning
/// potentially hundreds of draw calls into a single
/// `canvas.drawPicture()`.
class FreeDrawVisualEntry {
  FreeDrawVisualEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.path,
    required this.strokePath,
    required this.dottedPath,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final int pointCount;

  /// Smooth center-line path (for fill and stroke).
  final Path path;

  /// Dashed stroke path (null when not dashed).
  final Path? strokePath;

  /// Dotted stroke path (null when not dotted).
  final Path? dottedPath;

  /// Lazily computed flattened points for hit testing.
  ///
  /// Built on first access via [getOrBuildFlattened] and then
  /// reused for subsequent hit tests on the same element version.
  List<Offset>? _flattenedPoints;

  /// Lazily recorded picture for completed strokes.
  ///
  /// Keyed by opacity so that opacity changes invalidate the
  /// cached picture without rebuilding paths.
  Picture? _cachedPicture;
  double? _cachedPictureOpacity;

  /// Returns cached flattened points, building them on first call.
  List<Offset> getOrBuildFlattened(double strokeWidth) {
    if (_flattenedPoints != null) {
      return _flattenedPoints!;
    }
    _flattenedPoints = _flattenPath(path, math.max(1, strokeWidth).toDouble());
    return _flattenedPoints!;
  }

  /// Returns a cached [Picture] for the given [opacity], or null
  /// if none has been recorded yet.
  Picture? getCachedPicture(double opacity) {
    if (_cachedPicture != null && _cachedPictureOpacity == opacity) {
      return _cachedPicture;
    }
    return null;
  }

  /// Stores a recorded [Picture] for the given [opacity].
  void setCachedPicture(Picture picture, double opacity) {
    _cachedPicture?.dispose();
    _cachedPicture = picture;
    _cachedPictureOpacity = opacity;
  }

  /// Releases any native cached resources held by this entry.
  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedPictureOpacity = null;
  }

  bool matches(FreeDrawData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}

/// Shared LRU cache for free-draw visual data.
///
/// Both `FreeDrawRenderer` and `FreeDrawHitTester` resolve entries
/// through this singleton so the expensive smooth-path computation
/// happens at most once per element version.
class FreeDrawVisualCache {
  FreeDrawVisualCache._();

  static final instance = FreeDrawVisualCache._();

  final _entries = LruCache<String, FreeDrawVisualEntry>(maxEntries: 256);

  /// Resolves (or builds) the visual entry for [element].
  FreeDrawVisualEntry resolve({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries.get(id);
    if (existing != null && existing.matches(data, width, height)) {
      return existing;
    }

    // Try incremental path building when only the tail changed.
    final entry = _buildEntry(element: element, data: data, previous: existing);
    if (existing != null) {
      existing.dispose();
    }
    _entries.put(id, entry);
    return entry;
  }

  FreeDrawVisualEntry _buildEntry({
    required ElementState element,
    required FreeDrawData data,
    FreeDrawVisualEntry? previous,
  }) {
    final rect = element.rect;
    final localPoints = resolveFreeDrawLocalPoints(
      rect: rect,
      points: data.points,
    );
    if (localPoints.length < 2) {
      return FreeDrawVisualEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        pointCount: localPoints.length,
        path: Path(),
        strokePath: null,
        dottedPath: null,
      );
    }

    // Attempt incremental path extension when the previous entry
    // has the same data identity prefix (i.e. points were only
    // appended, not modified). This is the common case during
    // active drawing.
    Path? basePath;
    if (previous != null &&
        previous.pointCount >= 3 &&
        localPoints.length > previous.pointCount &&
        data.strokeStyle == StrokeStyle.solid) {
      basePath = buildFreeDrawSmoothPathIncremental(
        allPoints: localPoints,
        basePath: previous.path,
        basePointCount: previous.pointCount,
      );
    }
    basePath ??= buildFreeDrawSmoothPath(localPoints);

    Path? strokePath;
    Path? dottedPath;

    if (data.strokeWidth > 0) {
      switch (data.strokeStyle) {
        case StrokeStyle.solid:
          strokePath = basePath;
        case StrokeStyle.dashed:
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          strokePath = _buildDashedPath(basePath, dashLength, gapLength);
        case StrokeStyle.dotted:
          final dotSpacing = data.strokeWidth * 2.0;
          final dotRadius = data.strokeWidth * 0.5;
          dottedPath = _buildDottedPath(basePath, dotSpacing, dotRadius);
      }
    }

    return FreeDrawVisualEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      pointCount: localPoints.length,
      path: basePath,
      strokePath: strokePath,
      dottedPath: dottedPath,
    );
  }
}

// ============================================================
// Path helpers (shared with cache)
// ============================================================

Path _buildDashedPath(Path basePath, double dashLength, double gapLength) {
  final dashed = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dashLength, metric.length);
      dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next + gapLength;
    }
  }
  return dashed;
}

Path _buildDottedPath(Path basePath, double dotSpacing, double dotRadius) {
  final dotted = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        dotted.addOval(
          Rect.fromCircle(center: tangent.position, radius: dotRadius),
        );
      }
      distance += dotSpacing;
    }
  }
  return dotted;
}

List<Offset> _flattenPath(Path path, double step) {
  if (step <= 0) {
    return const <Offset>[];
  }

  var totalPathLength = 0.0;
  for (final metric in path.computeMetrics()) {
    totalPathLength += metric.length;
  }
  final needed = (totalPathLength / step).ceil() + 1;
  final maxPoints = needed.clamp(512, 8192);

  final flattened = <Offset>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    var distance = 0.0;
    while (distance < length && flattened.length < maxPoints) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        final point = tangent.position;
        if (flattened.isEmpty || point != flattened.last) {
          flattened.add(point);
        }
      }
      distance += step;
    }
    if (flattened.length >= maxPoints) {
      break;
    }
    final endTangent = metric.getTangentForOffset(length);
    if (endTangent != null) {
      final point = endTangent.position;
      if (flattened.isEmpty || point != flattened.last) {
        flattened.add(point);
      }
    }
  }
  return flattened;
}
