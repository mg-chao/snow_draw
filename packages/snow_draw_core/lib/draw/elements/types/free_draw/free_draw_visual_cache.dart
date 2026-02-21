import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../../utils/stroke_pattern_utils.dart';
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
/// once geometry remains stable for consecutive frames and then
/// replayed, turning potentially hundreds of draw calls into a
/// single `canvas.drawPicture()`.
class FreeDrawVisualEntry {
  FreeDrawVisualEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.path,
    required this.strokePath,
    this.dotPositions,
    this.dotRadius = 0,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final int pointCount;

  /// Smooth center-line path (for fill and stroke).
  final Path path;

  /// Dashed stroke path (null when not dashed).
  final Path? strokePath;

  /// Pre-computed dot center positions for dotted strokes.
  ///
  /// Stored as a flat [Float32List] of (x, y) pairs for use with
  /// [Canvas.drawRawPoints], which batches all dots into a single
  /// GPU draw call instead of tessellating individual ovals.
  final Float32List? dotPositions;

  /// Radius of each dot for dotted strokes.
  final double dotRadius;

  /// Lazily computed flattened points for hit testing.
  ///
  /// Built on first access via [getOrBuildFlattened] and then
  /// reused for subsequent hit tests on the same element version.
  List<Offset>? _flattenedPoints;

  /// Lazily converted flattened points in pure-core coordinates.
  List<DrawPoint>? _flattenedDrawPoints;

  /// Lazily built closed copy of [path] for fill hit testing.
  ///
  /// Avoids allocating and copying a new [Path] on every
  /// `hitTest` / render call for filled free-draw shapes.
  Path? _closedFillPath;

  /// Lazily flattened closed fill outline for pure geometry hit testing.
  List<DrawPoint>? _closedFillOutlinePoints;

  /// Lazily recorded picture for completed strokes.
  ///
  /// Keyed by opacity so that opacity changes invalidate the
  /// cached picture without rebuilding paths.
  Picture? _cachedPicture;
  double? _cachedPictureOpacity;
  double? _pictureCandidateOpacity;
  var _pictureCandidateFrameCount = 0;

  /// Returns cached flattened points, building them on first call.
  ///
  /// Uses a coarser step than rendering (2x stroke width) because
  /// hit testing only needs segment-level precision, not pixel-
  /// level smoothness. This halves the number of native
  /// `getTangentForOffset` calls.
  List<Offset> getOrBuildFlattened(double strokeWidth) {
    if (_flattenedPoints != null) {
      return _flattenedPoints!;
    }
    final step = math.max(2, strokeWidth * 2).toDouble();
    _flattenedPoints = _flattenPath(path, step);
    return _flattenedPoints!;
  }

  /// Returns flattened points as [DrawPoint] for pure geometry hit testing.
  List<DrawPoint> getOrBuildFlattenedPoints(double strokeWidth) {
    if (_flattenedDrawPoints != null) {
      return _flattenedDrawPoints!;
    }
    final flattened = getOrBuildFlattened(strokeWidth);
    _flattenedDrawPoints = List<DrawPoint>.unmodifiable(
      flattened.map((point) => DrawPoint(x: point.dx, y: point.dy)),
    );
    return _flattenedDrawPoints!;
  }

  /// Returns a cached closed copy of [path] for fill hit testing.
  ///
  /// Built once on first access and reused for subsequent calls,
  /// avoiding a native [Path] allocation + copy on every hit test.
  Path getOrBuildClosedFillPath() {
    if (_closedFillPath != null) {
      return _closedFillPath!;
    }
    _closedFillPath = Path()
      ..addPath(path, Offset.zero)
      ..close();
    return _closedFillPath!;
  }

  /// Returns flattened closed fill outline for point-in-polygon hit testing.
  List<DrawPoint> getOrBuildClosedFillOutlinePoints(double strokeWidth) {
    if (_closedFillOutlinePoints != null) {
      return _closedFillOutlinePoints!;
    }
    final step = math.max(1, strokeWidth).toDouble();
    final flattened = _flattenPath(getOrBuildClosedFillPath(), step);
    _closedFillOutlinePoints = List<DrawPoint>.unmodifiable(
      flattened.map((point) => DrawPoint(x: point.dx, y: point.dy)),
    );
    return _closedFillOutlinePoints!;
  }

  /// Returns a cached [Picture] for [opacity], or null if unavailable.
  Picture? getCachedPicture(double opacity) =>
      _cachedPictureOpacity == opacity ? _cachedPicture : null;

  /// Returns true once this geometry has remained stable long enough
  /// to justify recording a reusable [Picture].
  ///
  /// Transient geometries (for example while resizing) often live for a
  /// single frame. Deferring picture recording avoids expensive
  /// `PictureRecorder` churn on those one-frame entries.
  bool shouldRecordPicture(double opacity) {
    if (_cachedPicture != null && _cachedPictureOpacity == opacity) {
      return false;
    }
    if (_pictureCandidateOpacity != opacity) {
      _pictureCandidateOpacity = opacity;
      _pictureCandidateFrameCount = 0;
    }
    _pictureCandidateFrameCount += 1;
    return _pictureCandidateFrameCount >= 2;
  }

  /// Stores a recorded [Picture] for the given [opacity].
  void setCachedPicture(Picture picture, double opacity) {
    _cachedPicture?.dispose();
    _cachedPicture = picture;
    _cachedPictureOpacity = opacity;
    _pictureCandidateOpacity = opacity;
    _pictureCandidateFrameCount = 0;
  }

  /// Releases any native cached resources held by this entry.
  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedPictureOpacity = null;
    _pictureCandidateOpacity = null;
    _pictureCandidateFrameCount = 0;
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

  final _entries = LruCache<String, FreeDrawVisualEntry>(
    maxEntries: 256,
    onEvict: (entry) => entry.dispose(),
  );

  /// Clears all cached entries and disposes native resources.
  void clear() {
    _entries.clear();
  }

  @visibleForTesting
  int get entryCount => _entries.length;

  /// Resolves (or builds) the visual entry for [element].
  FreeDrawVisualEntry resolve({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries.get(id);
    if (existing != null) {
      if (existing.matches(data, width, height)) {
        return existing;
      }
      if (identical(existing.data, data)) {
        final resized = _buildEntryFromPreviousGeometry(
          data: data,
          previous: existing,
          width: width,
          height: height,
        );
        if (resized != null) {
          _entries.put(id, resized);
          return resized;
        }
      }
    }

    final entry = _buildEntry(element: element, data: data);
    // The LRU's onEvict callback handles disposing the old entry.
    _entries.put(id, entry);
    return entry;
  }

  FreeDrawVisualEntry _buildEntry({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final rect = element.rect;
    final localPoints = resolveFreeDrawLocalPoints(
      rect: rect,
      points: data.points,
    );
    final basePath = localPoints.length < 2
        ? Path()
        : buildFreeDrawSmoothPath(localPoints);

    final strokeVisuals = _buildStrokeVisuals(data: data, basePath: basePath);

    return FreeDrawVisualEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      pointCount: localPoints.length,
      path: basePath,
      strokePath: strokeVisuals.strokePath,
      dotPositions: strokeVisuals.dotPositions,
      dotRadius: strokeVisuals.dotRadius,
    );
  }

  FreeDrawVisualEntry? _buildEntryFromPreviousGeometry({
    required FreeDrawData data,
    required FreeDrawVisualEntry previous,
    required double width,
    required double height,
  }) {
    final previousWidth = previous.width;
    final previousHeight = previous.height;
    if (previousWidth <= 0 ||
        previousHeight <= 0 ||
        !previousWidth.isFinite ||
        !previousHeight.isFinite) {
      return null;
    }

    final scaleX = width / previousWidth;
    final scaleY = height / previousHeight;
    if (!scaleX.isFinite || !scaleY.isFinite || scaleX <= 0 || scaleY <= 0) {
      return null;
    }

    final basePath = _scalePath(previous.path, scaleX, scaleY);
    final strokeVisuals = _buildStrokeVisuals(data: data, basePath: basePath);
    return FreeDrawVisualEntry(
      data: data,
      width: width,
      height: height,
      pointCount: previous.pointCount,
      path: basePath,
      strokePath: strokeVisuals.strokePath,
      dotPositions: strokeVisuals.dotPositions,
      dotRadius: strokeVisuals.dotRadius,
    );
  }

  _StrokeVisuals _buildStrokeVisuals({
    required FreeDrawData data,
    required Path basePath,
  }) {
    if (data.strokeWidth <= 0) {
      return const _StrokeVisuals();
    }

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        return const _StrokeVisuals();
      case StrokeStyle.dashed:
        final dashLength = data.strokeWidth * 2.0;
        return _StrokeVisuals(
          strokePath: buildDashedPath(basePath, dashLength, dashLength * 1.2),
        );
      case StrokeStyle.dotted:
        return _StrokeVisuals(
          dotPositions: buildDotPositions(basePath, data.strokeWidth * 2.0),
          dotRadius: data.strokeWidth * 0.5,
        );
    }
  }
}

// ============================================================
// Path helpers (shared with cache)
// ============================================================

List<Offset> _flattenPath(Path path, double step) {
  if (step <= 0 || !step.isFinite) {
    return const <Offset>[];
  }

  const maxPoints = 4096;
  final flattened = <Offset>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    var distance = 0.0;
    while (distance < length) {
      if (flattened.length >= maxPoints) {
        return flattened;
      }
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
      return flattened;
    }
    final endTangent = metric.getTangentForOffset(length);
    if (endTangent != null) {
      final point = endTangent.position;
      if (flattened.isEmpty || point != flattened.last) {
        flattened.add(point);
        if (flattened.length >= maxPoints) {
          return flattened;
        }
      }
    }
  }
  return flattened;
}

Path _scalePath(Path source, double scaleX, double scaleY) {
  final matrix = Float64List(16)
    ..[0] = scaleX
    ..[5] = scaleY
    ..[10] = 1
    ..[15] = 1;
  return source.transform(matrix);
}

class _StrokeVisuals {
  const _StrokeVisuals({
    this.strokePath,
    this.dotPositions,
    this.dotRadius = 0,
  });

  final Path? strokePath;
  final Float32List? dotPositions;
  final double dotRadius;
}
