import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_like_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

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
  });

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

  /// Lazily built closed copy of [shaftPath] for fill hit testing.
  Path? _closedFillPath;
  List<DrawPoint>? _closedFillOutlinePoints;

  bool matches(ArrowLikeData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;

  /// Returns a cached closed copy of [shaftPath] for fill testing.
  ///
  /// Built once on first access, avoiding a native [Path]
  /// allocation + copy on every hit test for filled lines.
  Path getOrBuildClosedFillPath() {
    if (_closedFillPath != null) {
      return _closedFillPath!;
    }
    _closedFillPath = Path()
      ..addPath(shaftPath, Offset.zero)
      ..close();
    return _closedFillPath!;
  }

  /// Returns flattened closed fill outline for pure geometry hit testing.
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
    final shaftPath = ArrowGeometry.buildShaftPathFromResolvedPoints(
      points: geometry.insetPoints,
      arrowType: data.arrowType,
    );

    final arrowheadPaths = _buildArrowheadPaths(geometry);

    Path? combinedStrokePath;
    Float32List? dotPositions;
    double dotRadius = 0;

    if (data.strokeWidth > 0) {
      switch (data.strokeStyle) {
        case StrokeStyle.solid:
          combinedStrokePath = _combineStrokePaths(shaftPath, arrowheadPaths);
        case StrokeStyle.dashed:
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          final metrics = shaftPath.computeMetrics().toList(growable: false);
          final dashedShaft = _buildDashedPath(
            metrics: metrics,
            dashLength: dashLength,
            gapLength: gapLength,
          );
          combinedStrokePath = _combineStrokePaths(dashedShaft, arrowheadPaths);
        case StrokeStyle.dotted:
          final dotSpacing = data.strokeWidth * 2.0;
          dotRadius = data.strokeWidth * 0.5;
          final metrics = shaftPath.computeMetrics().toList(growable: false);
          dotPositions = _buildDotPositions(
            metrics: metrics,
            dotSpacing: dotSpacing,
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
    );
  }

  List<Path> _buildArrowheadPaths(ArrowGeometryDescriptor geometry) {
    final points = geometry.localPoints;
    final data = geometry.data;
    if (data.strokeWidth <= 0) {
      return const [];
    }

    final paths = <Path>[];
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

  Path _buildDashedPath({
    required List<PathMetric> metrics,
    required double dashLength,
    required double gapLength,
  }) {
    final dashed = Path();
    for (final metric in metrics) {
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
  Float32List _buildDotPositions({
    required List<PathMetric> metrics,
    required double dotSpacing,
  }) {
    // Count dots first to pre-allocate the Float32List.
    var dotCount = 0;
    for (final metric in metrics) {
      if (metric.length <= 0) {
        continue;
      }
      // Number of dots: floor(length / spacing) + 1 for the start.
      dotCount += (metric.length / dotSpacing).floor() + 1;
    }

    final positions = Float32List(dotCount * 2);
    var idx = 0;
    for (final metric in metrics) {
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

final arrowVisualCache = ArrowVisualCache();
