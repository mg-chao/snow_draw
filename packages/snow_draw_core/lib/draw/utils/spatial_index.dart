import 'package:rbush/rbush.dart';

import '../core/coordinates/element_space.dart';
import '../models/element_state.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

class SpatialIndex {
  SpatialIndex() : _tree = RBushDirect<String>();

  factory SpatialIndex.fromElements(List<ElementState> elements) =>
      SpatialIndex()..bulkLoad(elements);
  final RBushDirect<String> _tree;

  void bulkLoad(List<ElementState> elements) {
    if (elements.isEmpty) {
      return;
    }
    final items = elements.map(_entryFromElement).toList();
    _tree.load(items);
  }

  void insert(ElementState element) {
    _tree.insert(_boxFromElement(element), element.id);
  }

  void remove(ElementState element) {
    _tree.remove(element.id);
  }

  List<String> searchPoint(DrawPoint point, double tolerance) {
    final results = _tree.search(
      RBushBox(
        minX: point.x - tolerance,
        minY: point.y - tolerance,
        maxX: point.x + tolerance,
        maxY: point.y + tolerance,
      ),
    );
    return results.toList();
  }

  List<String> searchRect(DrawRect rect) {
    final results = _tree.search(
      RBushBox(
        minX: rect.minX,
        minY: rect.minY,
        maxX: rect.maxX,
        maxY: rect.maxY,
      ),
    );
    return results.toList();
  }

  List<String> getAllIds() => _tree.all();

  int get size => _tree.all().length;

  void clear() => _tree.clear();

  RBushElement<String> _entryFromElement(ElementState element) {
    final rect = _aabbFromElement(element);
    return RBushElement<String>(
      minX: rect.minX,
      minY: rect.minY,
      maxX: rect.maxX,
      maxY: rect.maxY,
      data: element.id,
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
