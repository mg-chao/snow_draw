import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../utils/spatial_index.dart';
import 'element_state.dart';

/// Persistent document data (lowest change frequency).
@immutable
class DocumentState {
  DocumentState({this.elements = const [], this.elementsVersion = 0});

  /// All elements on the canvas, ordered by z-index.
  final List<ElementState> elements;

  /// Version counter for element list changes.
  final int elementsVersion;

  late final _elementMap = Map<String, ElementState>.unmodifiable({
    for (final element in elements) element.id: element,
  });

  late final _orderIndex = Map<String, int>.unmodifiable({
    for (var i = 0; i < elements.length; i++) elements[i].id: i,
  });

  late final _spatialIndex = SpatialIndex.fromElements(elements);

  Map<String, ElementState> get elementMap => _elementMap;

  ElementState? getElementById(String id) => _elementMap[id];

  int? getOrderIndex(String id) => _orderIndex[id];

  SpatialIndex get spatialIndex => _spatialIndex;

  /// Touch lazy caches eagerly to avoid stalls during interactive work.
  int warmCaches() =>
      _elementMap.length + _orderIndex.length + _spatialIndex.size;

  List<ElementState> getElementsAtPoint(DrawPoint point, double tolerance) {
    final entries = _spatialIndex.searchPointEntries(point, tolerance);
    return _elementsForEntries(entries);
  }

  bool hasElementAtPoint(DrawPoint point, double tolerance) =>
      _spatialIndex.searchPointEntries(point, tolerance).isNotEmpty;

  List<ElementState> getElementsInRect(DrawRect rect) {
    final entries = _spatialIndex.searchRectEntries(rect);
    return _elementsForEntries(entries);
  }

  List<ElementState> _elementsForEntries(Iterable<SpatialIndexEntry> entries) {
    final elements = <ElementState>[];
    for (final entry in entries) {
      final element = getElementById(entry.id);
      if (element != null) {
        elements.add(element);
      }
    }
    return elements;
  }

  DocumentState copyWith({List<ElementState>? elements, int? elementsVersion}) {
    if (elements != null) {
      final nextVersion =
          elementsVersion ??
          (identical(elements, this.elements)
              ? this.elementsVersion
              : this.elementsVersion + 1);
      return DocumentState(elements: elements, elementsVersion: nextVersion);
    }

    return DocumentState(
      elements: this.elements,
      elementsVersion: elementsVersion ?? this.elementsVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentState &&
          identical(other.elements, elements) &&
          other.elementsVersion == elementsVersion;

  @override
  int get hashCode => Object.hash(elements, elementsVersion);

  @override
  String toString() =>
      'DocumentState(elements: ${elements.length}, version: $elementsVersion)';
}
