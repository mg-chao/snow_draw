import 'dart:math' as math;
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowVisualCacheEntry {
  ArrowVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.localPoints,
    required this.shaftPath,
    required this.arrowheadPaths,
    required this.combinedStrokePath,
    required this.dottedShaftPath,
  });

  final ArrowData data;
  final double width;
  final double height;
  final List<Offset> localPoints;
  final Path shaftPath;
  final List<Path> arrowheadPaths;
  final Path? combinedStrokePath;
  final Path? dottedShaftPath;

  bool matches(ArrowData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}

class ArrowVisualCache {
  ArrowVisualCache({int maxEntries = 1024}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final _entries = <String, ArrowVisualCacheEntry>{};

  ArrowVisualCacheEntry resolve({
    required ElementState element,
    required ArrowData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries[id];
    if (existing != null && existing.matches(data, width, height)) {
      _touch(id, existing);
      return existing;
    }

    final entry = _buildEntry(element: element, data: data);
    _entries[id] = entry;
    if (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return entry;
  }

  void clear() => _entries.clear();

  void _touch(String id, ArrowVisualCacheEntry entry) {
    _entries.remove(id);
    _entries[id] = entry;
  }

  ArrowVisualCacheEntry _buildEntry({
    required ElementState element,
    required ArrowData data,
  }) {
    final rect = element.rect;
    final localPoints = ArrowGeometry.resolveLocalPoints(
      rect: rect,
      normalizedPoints: data.points,
    );

    if (localPoints.length < 2 || data.strokeWidth <= 0) {
      return ArrowVisualCacheEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        localPoints: localPoints,
        shaftPath: Path(),
        arrowheadPaths: const [],
        combinedStrokePath: null,
        dottedShaftPath: null,
      );
    }

    final startInset = ArrowGeometry.calculateArrowheadInset(
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final endInset = ArrowGeometry.calculateArrowheadInset(
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final startDirectionOffset =
        ArrowGeometry.calculateArrowheadDirectionOffset(
          style: data.startArrowhead,
          strokeWidth: data.strokeWidth,
        );
    final endDirectionOffset =
        ArrowGeometry.calculateArrowheadDirectionOffset(
          style: data.endArrowhead,
          strokeWidth: data.strokeWidth,
        );

    final shaftPath = ArrowGeometry.buildShaftPath(
      points: localPoints,
      arrowType: data.arrowType,
      startInset: startInset,
      endInset: endInset,
    );

    final arrowheadPaths = _buildArrowheadPaths(
      localPoints,
      data,
      startInset: startInset,
      endInset: endInset,
      startDirectionOffset: startDirectionOffset,
      endDirectionOffset: endDirectionOffset,
    );

    Path? combinedStrokePath;
    Path? dottedShaftPath;

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        combinedStrokePath = _combineStrokePaths(shaftPath, arrowheadPaths);
      case StrokeStyle.dashed:
        final dashLength = data.strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        final dashedShaft = _buildDashedPath(
          shaftPath,
          dashLength,
          gapLength,
        );
        combinedStrokePath = _combineStrokePaths(dashedShaft, arrowheadPaths);
      case StrokeStyle.dotted:
        final dotSpacing = data.strokeWidth * 2.0;
        final dotRadius = data.strokeWidth * 0.5;
        dottedShaftPath = _buildDottedPath(
          shaftPath,
          dotSpacing,
          dotRadius,
        );
    }

    return ArrowVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      localPoints: localPoints,
      shaftPath: shaftPath,
      arrowheadPaths: arrowheadPaths,
      combinedStrokePath: combinedStrokePath,
      dottedShaftPath: dottedShaftPath,
    );
  }

  List<Path> _buildArrowheadPaths(
    List<Offset> points,
    ArrowData data, {
    required double startInset,
    required double endInset,
    required double startDirectionOffset,
    required double endDirectionOffset,
  }) {
    final paths = <Path>[];
    if (points.length < 2 || data.strokeWidth <= 0) {
      return paths;
    }

    final startDirection = ArrowGeometry.resolveStartDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: startDirectionOffset,
    );
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

    final endDirection = ArrowGeometry.resolveEndDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: endDirectionOffset,
    );
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
}

final arrowVisualCache = ArrowVisualCache();
