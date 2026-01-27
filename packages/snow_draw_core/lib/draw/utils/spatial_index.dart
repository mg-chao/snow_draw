import 'package:meta/meta.dart';
import 'package:rbush/rbush.dart';

import '../core/coordinates/element_space.dart';
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

  List<String> searchPoint(DrawPoint point, double tolerance) {
    final results = _tree.search(
      RBushBox(
        minX: point.x - tolerance,
        minY: point.y - tolerance,
        maxX: point.x + tolerance,
        maxY: point.y + tolerance,
      ),
    ).toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return results.map((entry) => entry.id).toList(growable: false);
  }

  List<String> searchRect(DrawRect rect) {
    final results = _tree.search(
      RBushBox(
        minX: rect.minX,
        minY: rect.minY,
        maxX: rect.maxX,
        maxY: rect.maxY,
      ),
    ).toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return results.map((entry) => entry.id).toList(growable: false);
  }

  List<String> getAllIds() =>
      _tree.all().map((entry) => entry.id).toList(growable: false);

  int get size => _tree.all().length;

  void clear() => _tree.clear();

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
    final space = ElementSpace(rotation: rotation, origin: center);
    final halfWidth = rect.width / 2;
    final halfHeight = rect.height / 2;

    final corners = <DrawPoint>[
      DrawPoint(x: center.x - halfWidth, y: center.y - halfHeight),
      DrawPoint(x: center.x + halfWidth, y: center.y - halfHeight),
      DrawPoint(x: center.x + halfWidth, y: center.y + halfHeight),
      DrawPoint(x: center.x - halfWidth, y: center.y + halfHeight),
    ];

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final corner in corners) {
      final rotated = space.toWorld(corner);
      final x = rotated.x;
      final y = rotated.y;
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

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
