import 'dart:ui';

import 'package:snow_draw_engine/snow_draw_engine.dart';

import '../geometry/arrow_geometry.dart';

class ArrowVisualCacheEntry {
  ArrowVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.geometry,
    required this.shaftPath,
    required this.arrowheadPaths,
  });

  final ArrowLikeData data;
  final double width;
  final double height;
  final FlutterArrowGeometryDescriptor geometry;
  final Path shaftPath;
  final FlutterArrowheadPaths arrowheadPaths;

  bool matches(ArrowLikeData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
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
    final geometry = FlutterArrowGeometryDescriptor(data: data, rect: rect);
    final shaftPath = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
      points: geometry.insetPoints,
      arrowType: data.arrowType,
    );

    final arrowheadPaths = _buildArrowheadPaths(geometry);

    return ArrowVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      geometry: geometry,
      shaftPath: shaftPath,
      arrowheadPaths: arrowheadPaths,
    );
  }

  FlutterArrowheadPaths _buildArrowheadPaths(
    FlutterArrowGeometryDescriptor geometry,
  ) {
    final points = geometry.localPoints;
    final data = geometry.data;
    if (data.strokeWidth <= 0) {
      return FlutterArrowheadPaths.empty();
    }

    final strokePath = Path();
    final fillPath = Path();
    final startDirection = geometry.startDirection;
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      final startPaths = FlutterArrowGeometry.buildArrowheadPaths(
        points: points,
        arrowType: data.arrowType,
        style: data.startArrowhead,
        strokeStyle: data.strokeStyle,
        strokeWidth: data.strokeWidth,
        position: ArrowEndpointPosition.start,
        directionOverride: startDirection,
      );
      strokePath.addPath(startPaths.strokePath, Offset.zero);
      fillPath.addPath(startPaths.fillPath, Offset.zero);
    }

    final endDirection = geometry.endDirection;
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      final endPaths = FlutterArrowGeometry.buildArrowheadPaths(
        points: points,
        arrowType: data.arrowType,
        style: data.endArrowhead,
        strokeStyle: data.strokeStyle,
        strokeWidth: data.strokeWidth,
        position: ArrowEndpointPosition.end,
        directionOverride: endDirection,
      );
      strokePath.addPath(endPaths.strokePath, Offset.zero);
      fillPath.addPath(endPaths.fillPath, Offset.zero);
    }

    return FlutterArrowheadPaths(strokePath: strokePath, fillPath: fillPath);
  }
}

final arrowVisualCache = ArrowVisualCache();
