import 'package:meta/meta.dart';

import '../elements/types/serial_number/serial_number_data.dart';
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

  /// Cached set of text element IDs bound to serial numbers.
  ///
  /// Avoids an O(n) scan of all elements on every hit test when
  /// the serial-number tool is active.
  late final boundTextIds = Set<String>.unmodifiable(_buildBoundTextIds());

  Map<String, ElementState> get elementMap => _elementMap;

  ElementState? getElementById(String id) => _elementMap[id];

  int? getOrderIndex(String id) => _orderIndex[id];

  SpatialIndex get spatialIndex => _spatialIndex;

  /// Touch lazy caches eagerly to avoid stalls during interactive work.
  int warmCaches() =>
      _elementMap.length + _orderIndex.length + _spatialIndex.size;

  List<ElementState> getElementsAtPoint(DrawPoint point, double tolerance) {
    final result = <ElementState>[];
    visitElementsAtPointTopDown(point, tolerance, (element) {
      result.add(element);
      return true;
    });
    return result;
  }

  bool hasElementAtPoint(DrawPoint point, double tolerance) =>
      _spatialIndex.searchPointEntries(point, tolerance).isNotEmpty;

  List<ElementState> getElementsInRect(DrawRect rect) {
    final entries = _spatialIndex.searchRectEntries(rect);
    return _elementsForEntries(entries);
  }

  /// Queries elements intersecting [rect], sorted by ascending z-order.
  ///
  /// Optional order-index bounds allow callers to constrain results to a
  /// partial z-range without additional filtering/sorting at call sites.
  List<ElementState> queryElementsInRectOrdered(
    DrawRect rect, {
    int? minOrderIndex,
    int? maxOrderIndex,
  }) {
    final entries = _spatialIndex.searchRectEntries(rect, ascending: true);
    final result = <ElementState>[];
    for (final entry in entries) {
      final zIndex = entry.zIndex;
      if (minOrderIndex != null && zIndex < minOrderIndex) {
        continue;
      }
      if (maxOrderIndex != null && zIndex > maxOrderIndex) {
        continue;
      }
      final element = getElementById(entry.id);
      if (element != null) {
        result.add(element);
      }
    }
    return result;
  }

  /// Queries point candidates sorted from top-most to bottom-most.
  ///
  /// The returned list is a fresh snapshot and remains stable even when
  /// subsequent queries are executed.
  List<ElementState> queryElementsAtPointTopDown(
    DrawPoint point,
    double tolerance,
  ) {
    final result = <ElementState>[];
    visitElementsAtPointTopDown(point, tolerance, (element) {
      result.add(element);
      return true;
    });
    return result;
  }

  /// Visits point candidates from top-most to bottom-most z-order.
  ///
  /// Returning `false` from [visitor] stops iteration early.
  void visitElementsAtPointTopDown(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor,
  ) {
    final entries = _spatialIndex.searchPointEntries(point, tolerance);
    for (final entry in entries) {
      final element = getElementById(entry.id);
      if (element != null) {
        if (!visitor(element)) {
          return;
        }
      }
    }
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

  Set<String> _buildBoundTextIds() {
    final ids = <String>{};
    for (final element in elements) {
      final data = element.data;
      if (data is SerialNumberData && data.textElementId != null) {
        ids.add(data.textElementId!);
      }
    }
    return ids;
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
