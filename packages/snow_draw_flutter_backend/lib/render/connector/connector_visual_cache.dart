import 'dart:ui';

import 'package:snow_draw_engine/snow_draw_engine.dart';

import '../geometry/connector_geometry.dart';

class ConnectorVisualCacheEntry {
  ConnectorVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.geometry,
    required this.shaftPath,
    required this.arrowheadPaths,
  });

  final ConnectorData data;
  final double width;
  final double height;
  final FlutterConnectorGeometryDescriptor geometry;
  final Path shaftPath;
  final FlutterConnectorArrowheadPaths arrowheadPaths;

  bool matches(ConnectorData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}

class ConnectorVisualCache {
  ConnectorVisualCache({int maxEntries = 1024})
    : _entries = LruCache<String, ConnectorVisualCacheEntry>(
        maxEntries: maxEntries,
      );

  final LruCache<String, ConnectorVisualCacheEntry> _entries;

  ConnectorVisualCacheEntry resolve({
    required ElementState element,
    required ConnectorData data,
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

  ConnectorVisualCacheEntry _buildEntry({
    required ElementState element,
    required ConnectorData data,
  }) {
    final rect = element.rect;
    final geometry = FlutterConnectorGeometryDescriptor(data: data, rect: rect);
    final shaftPath = FlutterConnectorGeometry.buildShaftPathFromResolvedPoints(
      points: geometry.insetPoints,
      arrowType: data.arrowType,
    );

    final arrowheadPaths = _buildArrowheadPaths(geometry);

    return ConnectorVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      geometry: geometry,
      shaftPath: shaftPath,
      arrowheadPaths: arrowheadPaths,
    );
  }

  FlutterConnectorArrowheadPaths _buildArrowheadPaths(
    FlutterConnectorGeometryDescriptor geometry,
  ) {
    final points = geometry.localPoints;
    final data = geometry.data;
    if (data.strokeWidth <= 0) {
      return FlutterConnectorArrowheadPaths.empty();
    }

    final strokePath = Path();
    final fillPath = Path();
    final startDirection = geometry.startDirection;
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      final startPaths = FlutterConnectorGeometry.buildArrowheadPaths(
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
      final endPaths = FlutterConnectorGeometry.buildArrowheadPaths(
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

    return FlutterConnectorArrowheadPaths(
      strokePath: strokePath,
      fillPath: fillPath,
    );
  }
}

final connectorVisualCache = ConnectorVisualCache();
