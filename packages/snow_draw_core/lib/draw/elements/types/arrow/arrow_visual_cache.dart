import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';

class ArrowVisualCacheEntry {
  ArrowVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.geometry,
    required this.shaftPath,
    required this.arrowheadPaths,
    required this.combinedStrokePath,
    this.dotPositions,
    this.dotRadius = 0,
    List<PathMetric>? pathMetrics,
  }) : _pathMetrics = pathMetrics;

  final ArrowLikeData data;
  final double width;
  final double height;
  final ArrowGeometryDescriptor geometry;
  final Path shaftPath;
  final List<Path> arrowheadPaths;
  final Path? combinedStrokePath;

  /// Pre-computed dot center positions for dotted strokes.
  ///
  /// Stored as a flat [Float32List] of (x, y) pairs for use with
  /// [Canvas.drawRawPoints], which batches all dots into a single GPU
  /// draw call instead of tessellating individual ovals.
  final Float32List? dotPositions;

  /// Radius of each dot for dotted strokes.
  final double dotRadius;

  List<PathMetric>? _pathMetrics;

  bool matches(ArrowLikeData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;

  List<PathMetric> resolvePathMetrics() =>
      _pathMetrics ??= shaftPath.computeMetrics().toList(growable: false);
}

class ArrowVisualCache {
  ArrowVisualCache({int maxEntries = 1024})
    : _entries = LruCache<String, ArrowVisualCacheEntry>(
        maxEntries: maxEntries,
      );

  final LruCache<String, ArrowVisualCacheEntry> _entries;

  ArrowVisualCacheEntry resolve({
    required ElementState element,
    required ArrowLikeData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries.get(id);
    if (existing != null && existing.matches(data, width, height)) {
      return existing;
    }

    final entry = _buildEntry(element: element, data: data);
    _entries.put(id, entry);
    return entry;
  }

  void clear() => _entries.clear();

  ArrowVisualCacheEntry _buildEntry({
    required ElementState element,
    required ArrowLikeData data,
  }) {
    final rect = element.rect;
    final geometry = ArrowGeometryDescriptor(data: data, rect: rect);
    final localPoints = geometry.localPoints;

    if (localPoints.length < 2) {
      return ArrowVisualCacheEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        geometry: geometry,
        shaftPath: Path(),
        arrowheadPaths: const [],
        combinedStrokePath: null,
      );
    }

    final startInset = geometry.startInset;
    final endInset = geometry.endInset;

    final shaftPoints = (startInset <= 0 && endInset <= 0)
        ? localPoints
        : geometry.insetPoints;
    final shaftPath = ArrowGeometry.buildShaftPathFromResolvedPoints(
      points: shaftPoints,
      arrowType: data.arrowType,
    );

    final arrowheadPaths = _buildArrowheadPaths(geometry);

    Path? combinedStrokePath;
    Float32List? dotPositions;
    double dotRadius = 0;
    List<PathMetric>? pathMetrics;

    if (data.strokeWidth > 0) {
      switch (data.strokeStyle) {
        case StrokeStyle.solid:
          combinedStrokePath = _combineStrokePaths(shaftPath, arrowheadPaths);
        case StrokeStyle.dashed:
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          pathMetrics = shaftPath.computeMetrics().toList(growable: false);
          final dashedShaft = _buildDashedPath(
            shaftPath,
            dashLength,
            gapLength,
            metrics: pathMetrics,
          );
          combinedStrokePath = _combineStrokePaths(dashedShaft, arrowheadPaths);
        case StrokeStyle.dotted:
          final dotSpacing = data.strokeWidth * 2.0;
          dotRadius = data.strokeWidth * 0.5;
          pathMetrics = shaftPath.computeMetrics().toList(growable: false);
          dotPositions = _buildDotPositions(
            shaftPath,
            dotSpacing,
            metrics: pathMetrics,
          );
      }
    }

    return ArrowVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      geometry: geometry,
      shaftPath: shaftPath,
      arrowheadPaths: arrowheadPaths,
      combinedStrokePath: combinedStrokePath,
      dotPositions: dotPositions,
      dotRadius: dotRadius,
      pathMetrics: pathMetrics,
    );
  }

  List<Path> _buildArrowheadPaths(ArrowGeometryDescriptor geometry) {
    final paths = <Path>[];
    final points = geometry.localPoints;
    final data = geometry.data;
    if (points.length < 2 || data.strokeWidth <= 0) {
      return paths;
    }

    final startDirection = geometry.startDirection;
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      paths.add(
        ArrowGeometry.buildArrowheadPath(
          tip: points.first,
          direction: startDirection,
          style: data.startArrowhead,
          strokeWidth: data.strokeWidth,
        ),
      );
    }

    final endDirection = geometry.endDirection;
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      paths.add(
        ArrowGeometry.buildArrowheadPath(
          tip: points.last,
          direction: endDirection,
          style: data.endArrowhead,
          strokeWidth: data.strokeWidth,
        ),
      );
    }

    return paths;
  }

  Path _combineStrokePaths(Path shaftPath, List<Path> arrowheadPaths) {
    final combined = Path()..addPath(shaftPath, Offset.zero);
    for (final arrowhead in arrowheadPaths) {
      combined.addPath(arrowhead, Offset.zero);
    }
    return combined;
  }

  Path _buildDashedPath(
    Path basePath,
    double dashLength,
    double gapLength, {
    List<PathMetric>? metrics,
  }) {
    final dashed = Path();
    final resolved =
        metrics ?? basePath.computeMetrics().toList(growable: false);
    for (final metric in resolved) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gapLength;
      }
    }
    return dashed;
  }

  /// Builds a [Float32List] of dot center positions along the path.
  ///
  /// Returns (x, y) pairs suitable for [Canvas.drawRawPoints], which
  /// batches all dots into a single GPU draw call. This replaces the
  /// previous approach of adding individual ovals to a [Path], which
  /// required Impeller to tessellate each oval separately.
  Float32List _buildDotPositions(
    Path basePath,
    double dotSpacing, {
    List<PathMetric>? metrics,
  }) {
    final resolved =
        metrics ?? basePath.computeMetrics().toList(growable: false);

    // Count dots first to pre-allocate the Float32List.
    var dotCount = 0;
    for (final metric in resolved) {
      if (metric.length <= 0) {
        continue;
      }
      // Number of dots: floor(length / spacing) + 1 for the start.
      dotCount += (metric.length / dotSpacing).floor() + 1;
    }

    final positions = Float32List(dotCount * 2);
    var idx = 0;
    for (final metric in resolved) {
      var distance = 0.0;
      while (distance < metric.length) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          positions[idx++] = tangent.position.dx;
          positions[idx++] = tangent.position.dy;
        }
        distance += dotSpacing;
      }
    }

    // Trim if we over-estimated (e.g. getTangentForOffset returned null).
    if (idx < positions.length) {
      return Float32List.sublistView(positions, 0, idx);
    }
    return positions;
  }
}

final arrowVisualCache = ArrowVisualCache();
