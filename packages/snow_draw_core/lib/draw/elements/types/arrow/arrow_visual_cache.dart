import 'dart:math' as math;
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowVisualCacheEntry {
  ArrowVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.geometry,
    required this.shaftPath,
    required this.arrowheadPaths,
    required this.combinedStrokePath,
    required this.dottedShaftPath,
    List<PathMetric>? pathMetrics,
  }) : _pathMetrics = pathMetrics;

  final ArrowData data;
  final double width;
  final double height;
  final ArrowGeometryDescriptor geometry;
  final Path shaftPath;
  final List<Path> arrowheadPaths;
  final Path? combinedStrokePath;
  final Path? dottedShaftPath;
  List<PathMetric>? _pathMetrics;

  bool matches(ArrowData data, double width, double height) =>
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
    required ArrowData data,
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
    required ArrowData data,
  }) {
    final rect = element.rect;
    final geometry = ArrowGeometryDescriptor(data: data, rect: rect);
    final localPoints = geometry.localPoints;

    if (localPoints.length < 2 || data.strokeWidth <= 0) {
      return ArrowVisualCacheEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        geometry: geometry,
        shaftPath: Path(),
        arrowheadPaths: const [],
        combinedStrokePath: null,
        dottedShaftPath: null,
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
    Path? dottedShaftPath;
    List<PathMetric>? pathMetrics;

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
        final dotRadius = data.strokeWidth * 0.5;
        pathMetrics = shaftPath.computeMetrics().toList(growable: false);
        dottedShaftPath = _buildDottedPath(
          shaftPath,
          dotSpacing,
          dotRadius,
          metrics: pathMetrics,
        );
    }

    return ArrowVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      geometry: geometry,
      shaftPath: shaftPath,
      arrowheadPaths: arrowheadPaths,
      combinedStrokePath: combinedStrokePath,
      dottedShaftPath: dottedShaftPath,
      pathMetrics: pathMetrics,
    );
  }

  List<Path> _buildArrowheadPaths(
    ArrowGeometryDescriptor geometry,
  ) {
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
    final resolved = metrics ??
        basePath.computeMetrics().toList(growable: false);
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

  Path _buildDottedPath(
    Path basePath,
    double dotSpacing,
    double dotRadius, {
    List<PathMetric>? metrics,
  }) {
    final dotted = Path();
    final resolved = metrics ??
        basePath.computeMetrics().toList(growable: false);
    for (final metric in resolved) {
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
}

final arrowVisualCache = ArrowVisualCache();
