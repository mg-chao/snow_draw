import 'dart:ui';

import 'package:snow_draw_core/snow_draw_core.dart';

import 'free_draw_path_utils.dart';

/// Cached visual data for a single free-draw element.
///
/// The dynamic canvas currently needs only the smoothed path to render hover
/// outlines, so this entry keeps the cache payload intentionally small.
class FreeDrawVisualEntry {
  FreeDrawVisualEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.path,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final int pointCount;
  final Path path;

  bool matches(FreeDrawData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}

/// Shared LRU cache for free-draw hover-outline geometry.
class FreeDrawVisualCache {
  FreeDrawVisualCache._();

  static final instance = FreeDrawVisualCache._();

  final _entries = LruCache<String, FreeDrawVisualEntry>(maxEntries: 256);

  /// Clears all cached entries.
  void clear() {
    _entries.clear();
  }

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

    final entry = _buildEntry(element: element, data: data);
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
    final path = localPoints.length < 2
        ? Path()
        : buildFreeDrawSmoothPath(localPoints);

    return FreeDrawVisualEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      pointCount: localPoints.length,
      path: path,
    );
  }
}
