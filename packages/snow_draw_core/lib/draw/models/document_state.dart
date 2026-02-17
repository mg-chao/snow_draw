import 'package:meta/meta.dart';

import '../elements/types/arrow/arrow_binding.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/filter/filter_data.dart';
import '../elements/types/highlight/highlight_data.dart';
import '../elements/types/serial_number/serial_number_data.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../utils/spatial_index.dart';
import 'element_state.dart';
import 'global_elements_state.dart';

/// Persistent document data (lowest change frequency).
@immutable
class DocumentState {
  DocumentState({
    this.elements = const [],
    this.elementsVersion = 0,
    this.globalElements = const GlobalElementsState(),
  });

  /// All elements on the canvas, ordered by z-index.
  final List<ElementState> elements;

  /// Version counter for element-list changes.
  ///
  /// Global document elements (highlight mask/watermark) are versioned
  /// separately through value equality and should not invalidate
  /// element-scene caches tied to [elementsVersion].
  final int elementsVersion;

  /// Persistent global document elements.
  final GlobalElementsState globalElements;

  late final _elementMap = Map<String, ElementState>.unmodifiable({
    for (final element in elements) element.id: element,
  });

  late final _orderIndex = Map<String, int>.unmodifiable({
    for (var i = 0; i < elements.length; i++) elements[i].id: i,
  });

  late final _spatialIndex = SpatialIndex.fromElements(elements);

  late final _arrowBindableElements = List<ElementState>.unmodifiable(
    _buildArrowBindableElements(),
  );

  late final _arrowBindableSpatialIndex = SpatialIndex.fromElements(
    _arrowBindableElements,
  );

  /// Cached set of text element IDs bound to serial numbers.
  ///
  /// Avoids an O(n) scan of all elements on every hit test when
  /// the serial-number tool is active.
  late final boundTextIds = Set<String>.unmodifiable(_buildBoundTextIds());

  /// Cached set of element IDs currently used by bound arrow endpoints.
  ///
  /// This lets interaction fast paths cheaply determine whether moving a target
  /// element can implicitly preview-update dependent arrows.
  late final boundArrowTargetIds = Set<String>.unmodifiable(
    _buildBoundArrowTargetIds(),
  );

  /// Whether the document currently contains any bindable arrow targets.
  ///
  /// This lets arrow create/edit flows skip spatial queries entirely when no
  /// rectangle/text/serial-number elements are present.
  late final bool hasArrowBindableElements = _arrowBindableElements.isNotEmpty;

  /// Cached highlight elements in document z-order.
  ///
  /// The list is computed lazily once per [DocumentState] instance and reused
  /// by highlight-mask rendering paths to avoid repeated O(n) scans during
  /// high-frequency interactions.
  late final highlightElements = List<ElementState>.unmodifiable(
    _buildHighlightElements(),
  );

  /// Suffix cache for blend-sensitive element presence.
  ///
  /// Index `i` answers whether any highlight/filter element exists in
  /// `[i, elements.length)`, regardless of opacity.
  late final List<bool> _blendSensitiveSuffix = _buildBlendSensitiveSuffix(
    includeTransparent: true,
  );

  /// Suffix cache for visible blend-sensitive element presence.
  ///
  /// Index `i` answers whether any non-transparent highlight/filter element
  /// exists in `[i, elements.length)`.
  late final List<bool> _visibleBlendSensitiveSuffix =
      _buildBlendSensitiveSuffix(includeTransparent: false);

  /// Suffix cache for filter element presence.
  ///
  /// Index `i` answers whether any filter element exists in
  /// `[i, elements.length)`, regardless of opacity.
  late final List<bool> _filterSuffix = _buildFilterSuffix(
    includeTransparent: true,
  );

  /// Suffix cache for visible filter element presence.
  ///
  /// Index `i` answers whether any non-transparent filter element exists in
  /// `[i, elements.length)`.
  late final List<bool> _visibleFilterSuffix = _buildFilterSuffix(
    includeTransparent: false,
  );

  Map<String, ElementState> get elementMap => _elementMap;

  ElementState? getElementById(String id) => _elementMap[id];

  int? getOrderIndex(String id) => _orderIndex[id];

  /// Returns whether any blend-sensitive element exists at or above
  /// [orderIndex].
  ///
  /// Blend-sensitive elements are those whose rendering depends on draw order
  /// with surrounding pixels (currently highlight/filter).
  ///
  /// Set [includeTransparent] to `false` to only consider elements with
  /// positive opacity.
  bool hasBlendSensitiveElementFromOrderIndex(
    int orderIndex, {
    bool includeTransparent = true,
  }) {
    final normalizedIndex = _normalizeOrderIndex(orderIndex);
    final suffix = includeTransparent
        ? _blendSensitiveSuffix
        : _visibleBlendSensitiveSuffix;
    return suffix[normalizedIndex];
  }

  /// Returns whether any blend-sensitive element exists strictly above
  /// [orderIndex].
  ///
  /// This is equivalent to querying from `orderIndex + 1`.
  bool hasBlendSensitiveElementAboveOrderIndex(
    int orderIndex, {
    bool includeTransparent = true,
  }) => hasBlendSensitiveElementFromOrderIndex(
    orderIndex + 1,
    includeTransparent: includeTransparent,
  );

  /// Returns whether any filter element exists at or above [orderIndex].
  ///
  /// Set [includeTransparent] to `false` to only consider filters with
  /// positive opacity.
  bool hasFilterElementFromOrderIndex(
    int orderIndex, {
    bool includeTransparent = true,
  }) {
    final normalizedIndex = _normalizeOrderIndex(orderIndex);
    final suffix = includeTransparent ? _filterSuffix : _visibleFilterSuffix;
    return suffix[normalizedIndex];
  }

  /// Returns whether any filter element exists strictly above [orderIndex].
  ///
  /// This is equivalent to querying from `orderIndex + 1`.
  bool hasFilterElementAboveOrderIndex(
    int orderIndex, {
    bool includeTransparent = true,
  }) => hasFilterElementFromOrderIndex(
    orderIndex + 1,
    includeTransparent: includeTransparent,
  );

  SpatialIndex get spatialIndex => _spatialIndex;

  /// Visits bindable arrow targets in arbitrary order.
  ///
  /// This uses the bindable-only spatial index to avoid scanning unrelated
  /// elements during endpoint binding lookups.
  void visitArrowBindableElementsAtPoint(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor, {
    String? excludedElementId,
  }) {
    if (!hasArrowBindableElements) {
      return;
    }

    final entries = _arrowBindableSpatialIndex.searchPointEntries(
      point,
      tolerance,
      sortByZ: false,
    );
    for (final entry in entries) {
      final elementId = entry.id;
      if (excludedElementId != null && elementId == excludedElementId) {
        continue;
      }
      final element = _elementMap[elementId];
      if (element == null || element.opacity <= 0) {
        continue;
      }
      if (!visitor(element)) {
        return;
      }
    }
  }

  /// Touch lazy caches eagerly to avoid stalls during interactive work.
  int warmCaches() =>
      _elementMap.length +
      _orderIndex.length +
      _spatialIndex.size +
      _arrowBindableSpatialIndex.size +
      boundArrowTargetIds.length +
      highlightElements.length +
      _blendSensitiveSuffix.length +
      _visibleBlendSensitiveSuffix.length +
      _filterSuffix.length +
      _visibleFilterSuffix.length;

  /// Returns true when any element in [elementIds] has bound arrow endpoints.
  bool hasArrowBoundToAny(Iterable<String> elementIds) {
    if (boundArrowTargetIds.isEmpty) {
      return false;
    }
    for (final elementId in elementIds) {
      if (boundArrowTargetIds.contains(elementId)) {
        return true;
      }
    }
    return false;
  }

  List<ElementState> getElementsAtPoint(DrawPoint point, double tolerance) {
    final result = <ElementState>[];
    visitElementsAtPointTopDown(point, tolerance, (element) {
      result.add(element);
      return true;
    });
    return result;
  }

  bool hasElementAtPoint(DrawPoint point, double tolerance) => _spatialIndex
      .searchPointEntries(point, tolerance, sortByZ: false)
      .isNotEmpty;

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

  /// Visits point candidates in arbitrary order.
  ///
  /// This skips z-order sorting and is suitable for callers that only need
  /// geometric candidates (for example arrow binding resolution).
  void visitElementsAtPoint(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor,
  ) {
    final entries = _spatialIndex.searchPointEntries(
      point,
      tolerance,
      sortByZ: false,
    );
    for (final entry in entries) {
      final element = getElementById(entry.id);
      if (element != null) {
        if (!visitor(element)) {
          return;
        }
      }
    }
  }

  /// Visits rect-intersecting candidates in arbitrary order.
  ///
  /// This skips z-order sorting and is suitable for broad-phase queries where
  /// callers perform their own geometric checks.
  void visitElementsInRect(
    DrawRect rect,
    bool Function(ElementState element) visitor,
  ) {
    final entries = _spatialIndex.searchRectEntries(rect, sortByZ: false);
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

  Set<String> _buildBoundArrowTargetIds() {
    final ids = <String>{};
    for (final element in elements) {
      final data = element.data;
      if (data is! ArrowLikeData) {
        continue;
      }
      final startTargetId = data.startBinding?.elementId;
      if (startTargetId != null) {
        ids.add(startTargetId);
      }
      final endTargetId = data.endBinding?.elementId;
      if (endTargetId != null) {
        ids.add(endTargetId);
      }
    }
    return ids;
  }

  List<ElementState> _buildArrowBindableElements() {
    final bindable = <ElementState>[];
    for (final element in elements) {
      if (element.opacity <= 0) {
        continue;
      }
      if (ArrowBindingUtils.isBindableTarget(element)) {
        bindable.add(element);
      }
    }
    return bindable;
  }

  List<ElementState> _buildHighlightElements() {
    final highlights = <ElementState>[];
    for (final element in elements) {
      if (element.data is HighlightData) {
        highlights.add(element);
      }
    }
    return highlights;
  }

  List<bool> _buildBlendSensitiveSuffix({required bool includeTransparent}) {
    final suffix = List<bool>.filled(elements.length + 1, false);
    var hasBlendSensitive = false;

    for (var index = elements.length - 1; index >= 0; index--) {
      final element = elements[index];
      if (_isBlendSensitiveElement(
        element,
        includeTransparent: includeTransparent,
      )) {
        hasBlendSensitive = true;
      }
      suffix[index] = hasBlendSensitive;
    }

    return List<bool>.unmodifiable(suffix);
  }

  List<bool> _buildFilterSuffix({required bool includeTransparent}) {
    final suffix = List<bool>.filled(elements.length + 1, false);
    var hasFilter = false;

    for (var index = elements.length - 1; index >= 0; index--) {
      final element = elements[index];
      final data = element.data;
      final isFilter = data is FilterData;
      final isVisible = includeTransparent || element.opacity > 0;
      if (isFilter && isVisible) {
        hasFilter = true;
      }
      suffix[index] = hasFilter;
    }

    return List<bool>.unmodifiable(suffix);
  }

  bool _isBlendSensitiveElement(
    ElementState element, {
    required bool includeTransparent,
  }) {
    final data = element.data;
    final isBlendSensitive = data is HighlightData || data is FilterData;
    if (!isBlendSensitive) {
      return false;
    }
    if (includeTransparent) {
      return true;
    }
    return element.opacity > 0;
  }

  int _normalizeOrderIndex(int orderIndex) {
    if (orderIndex <= 0) {
      return 0;
    }
    final maxIndex = elements.length;
    if (orderIndex >= maxIndex) {
      return maxIndex;
    }
    return orderIndex;
  }

  DocumentState copyWith({
    List<ElementState>? elements,
    int? elementsVersion,
    GlobalElementsState? globalElements,
  }) {
    final nextElements = elements ?? this.elements;
    final nextGlobalElements = globalElements ?? this.globalElements;
    final hasElementsChanged = !identical(nextElements, this.elements);
    final nextVersion =
        elementsVersion ??
        (hasElementsChanged ? this.elementsVersion + 1 : this.elementsVersion);

    return DocumentState(
      elements: nextElements,
      elementsVersion: nextVersion,
      globalElements: nextGlobalElements,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentState &&
          identical(other.elements, elements) &&
          other.elementsVersion == elementsVersion &&
          other.globalElements == globalElements;

  @override
  int get hashCode => Object.hash(elements, elementsVersion, globalElements);

  @override
  String toString() =>
      'DocumentState('
      'elements: ${elements.length}, '
      'version: $elementsVersion, '
      'globalElements: $globalElements'
      ')';
}
