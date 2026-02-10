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
  SpatialIndex()
    : _tree = RBushDirect<SpatialIndexEntry>(),
      _pointSearchBuffer = <SpatialIndexEntry>[],
      _rectSearchBuffer = <SpatialIndexEntry>[],
      _pointIdBuffer = <String>[],
      _rectIdBuffer = <String>[];

  factory SpatialIndex.fromElements(List<ElementState> elements) =>
      SpatialIndex()..bulkLoad(elements);
  final RBushDirect<SpatialIndexEntry> _tree;
  final List<SpatialIndexEntry> _pointSearchBuffer;
  final List<SpatialIndexEntry> _rectSearchBuffer;
  final List<String> _pointIdBuffer;
  final List<String> _rectIdBuffer;

  void bulkLoad(List<ElementState> elements) {
    if (elements.isEmpty) {
      return;
    }
    final items = <RBushElement<SpatialIndexEntry>>[];
    for (var i = 0; i < elements.length; i++) {
      items.add(_entryFromElement(elements[i], i));
    }
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
  }) {
    final results = _tree.search(
      RBushBox(
        minX: point.x - tolerance,
        minY: point.y - tolerance,
        maxX: point.x + tolerance,
        maxY: point.y + tolerance,
      ),
    );
    final buffer = _pointSearchBuffer
      ..clear()
      ..addAll(results)
      ..sort(
        descending
            ? (a, b) => b.zIndex.compareTo(a.zIndex)
            : (a, b) => a.zIndex.compareTo(b.zIndex),
      );
    return buffer;
  }

  List<SpatialIndexEntry> searchRectEntries(
    DrawRect rect, {
    bool ascending = false,
  }) {
    final results = _tree.search(
      RBushBox(
        minX: rect.minX,
        minY: rect.minY,
        maxX: rect.maxX,
        maxY: rect.maxY,
      ),
    );
    final buffer = _rectSearchBuffer
      ..clear()
      ..addAll(results)
      ..sort(
        ascending
            ? (a, b) => a.zIndex.compareTo(b.zIndex)
            : (a, b) => b.zIndex.compareTo(a.zIndex),
      );
    return buffer;
  }

  List<String> searchPoint(DrawPoint point, double tolerance) {
    final results = searchPointEntries(point, tolerance);
    final ids = _pointIdBuffer..clear();
    for (final entry in results) {
      ids.add(entry.id);
    }
    return ids;
  }

  List<String> searchRect(DrawRect rect) {
    final results = searchRectEntries(rect);
    final ids = _rectIdBuffer..clear();
    for (final entry in results) {
      ids.add(entry.id);
    }
    return ids;
  }

  List<String> getAllIds() =>
      _tree.all().map((entry) => entry.id).toList(growable: false);

  int get size => _tree.all().length;

  void clear() {
    _tree.clear();
    _pointSearchBuffer.clear();
    _rectSearchBuffer.clear();
    _pointIdBuffer.clear();
    _rectIdBuffer.clear();
  }

  RBushElement<SpatialIndexEntry> _entryFromElement(
    ElementState element,
    int? orderIndex,
  ) {
    final rect = _aabbFromElement(element);
    return RBushElement<SpatialIndexEntry>(
      minX: rect.minX,
      minY: rect.minY,
      maxX: rect.maxX,
      maxY: rect.maxY,
      data: SpatialIndexEntry(
        id: element.id,
        zIndex: orderIndex ?? element.zIndex,
      ),
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
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final halfWidth = rect.width / 2;
    final halfHeight = rect.height / 2;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    void update(double dx, double dy) {
      final x = center.x + dx * cos - dy * sin;
      final y = center.y + dx * sin + dy * cos;
      if (x < minX) {
        minX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y > maxY) {
        maxY = y;
      }
    }

    update(-halfWidth, -halfHeight);
    update(halfWidth, -halfHeight);
    update(halfWidth, halfHeight);
    update(-halfWidth, halfHeight);

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
