import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:rbush/rbush.dart';
import '../models/element_state.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

@immutable
class SpatialIndexEntry {
  const SpatialIndexEntry({required this.id, required this.zIndex});

  final String id;
  final int zIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SpatialIndexEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SpatialIndex {
  SpatialIndex() : _tree = RBushDirect<SpatialIndexEntry>();

  factory SpatialIndex.fromElements(List<ElementState> elements) =>
      SpatialIndex()..bulkLoad(elements);
  final RBushDirect<SpatialIndexEntry> _tree;

  void bulkLoad(List<ElementState> elements) {
    if (elements.isEmpty) {
      return;
    }
    final items = List<RBushElement<SpatialIndexEntry>>.generate(
      elements.length,
      (index) => _entryFromElement(elements[index], index),
      growable: false,
    );
    _tree.load(items);
  }

  void insert(ElementState element) {
    _tree.insert(
      _boxFromElement(element),
      SpatialIndexEntry(id: element.id, zIndex: element.zIndex),
    );
  }

  void remove(ElementState element) {
    _tree.remove(SpatialIndexEntry(id: element.id, zIndex: element.zIndex));
  }

  List<SpatialIndexEntry> searchPointEntries(
    DrawPoint point,
    double tolerance, {
    bool descending = true,
    bool sortByZ = true,
  }) {
    final entries = _tree.search(
      RBushBox(
        minX: point.x - tolerance,
        minY: point.y - tolerance,
        maxX: point.x + tolerance,
        maxY: point.y + tolerance,
      ),
    );
    if (sortByZ && entries.length > 1) {
      entries.sort(
        descending
            ? (a, b) => b.zIndex.compareTo(a.zIndex)
            : (a, b) => a.zIndex.compareTo(b.zIndex),
      );
    }
    return entries;
  }

  List<SpatialIndexEntry> searchRectEntries(
    DrawRect rect, {
    bool ascending = false,
    bool sortByZ = true,
  }) {
    final entries = _tree.search(
      RBushBox(
        minX: rect.minX,
        minY: rect.minY,
        maxX: rect.maxX,
        maxY: rect.maxY,
      ),
    );
    if (sortByZ && entries.length > 1) {
      entries.sort(
        ascending
            ? (a, b) => a.zIndex.compareTo(b.zIndex)
            : (a, b) => b.zIndex.compareTo(a.zIndex),
      );
    }
    return entries;
  }

  List<String> searchPoint(DrawPoint point, double tolerance) =>
      searchPointEntries(point, tolerance).map((entry) => entry.id).toList();

  List<String> searchRect(DrawRect rect) =>
      searchRectEntries(rect).map((entry) => entry.id).toList();

  List<String> getAllIds() =>
      _tree.all().map((entry) => entry.id).toList(growable: false);

  int get size => _tree.all().length;

  void clear() => _tree.clear();

  RBushElement<SpatialIndexEntry> _entryFromElement(
    ElementState element,
    int zIndex,
  ) {
    final rect = _aabbFromElement(element);
    return RBushElement<SpatialIndexEntry>(
      minX: rect.minX,
      minY: rect.minY,
      maxX: rect.maxX,
      maxY: rect.maxY,
      data: SpatialIndexEntry(id: element.id, zIndex: zIndex),
    );
  }

  RBushBox _boxFromElement(ElementState element) {
    final rect = _aabbFromElement(element);
    return RBushBox(
      minX: rect.minX,
      minY: rect.minY,
      maxX: rect.maxX,
      maxY: rect.maxY,
    );
  }

  DrawRect _aabbFromElement(ElementState element) {
    final rect = element.rect;
    final rotation = element.rotation;
    if (rotation == 0) {
      return rect;
    }

    final center = rect.center;
    final halfWidth = rect.width.abs() / 2;
    final halfHeight = rect.height.abs() / 2;
    final cos = math.cos(rotation).abs();
    final sin = math.sin(rotation).abs();
    final extentX = cos * halfWidth + sin * halfHeight;
    final extentY = sin * halfWidth + cos * halfHeight;

    return DrawRect(
      minX: center.x - extentX,
      minY: center.y - extentY,
      maxX: center.x + extentX,
      maxY: center.y + extentY,
    );
  }
}
