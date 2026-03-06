import 'package:meta/meta.dart';
import '../elements/types/arrow/arrow_core.dart' as core;

import '../elements/types/arrow/arrow_core_bridge.dart';
import '../elements/types/connector/connector_data.dart';
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

  /// Version counter for persisted element changes.
  ///
  /// Includes both regular element-list mutations and global element updates
  /// (for example highlight-mask and watermark config changes) so downstream
  /// scene/event consumers can treat them uniformly.
  final int elementsVersion;

  /// Persistent global document elements.
  final GlobalElementsState globalElements;

  late final _elementMap = Map<String, ElementState>.unmodifiable({
    for (final element in elements) element.id: element,
  });

  late final _orderIndex = Map<String, int>.unmodifiable({
    for (var i = 0; i < elements.length; i++) elements[i].id: i,
  });

  /// Ordered element ids mirroring [elements] z-order.
  ///
  /// Useful for arrow-core reorder reductions without rebuilding id lists.
  late final orderedElementIds = List<String>.unmodifiable(
    elements.map((element) => element.id),
  );

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
  /// bindable shapes are present.
  late final bool hasArrowBindableElements = _arrowBindableElements.isNotEmpty;

  /// Cached bindable snapshots projected for arrow operations.
  ///
  /// Reused by high-frequency arrow interactions to avoid repeatedly
  /// re-projecting static bindable geometry for the same document version.
  late final _arrowBindableStates = List<core.BindableState>.unmodifiable(
    collectCoreBindables(elements),
  );

  /// Cached bindables keyed by id for fast arrow candidate resolution.
  ///
  /// This avoids rebuilding bindable projections in high-frequency pointer
  /// interactions.
  late final _arrowBindableStateById =
      Map<String, core.BindableState>.unmodifiable({
        for (final bindable in _arrowBindableStates) bindable.id: bindable,
      });

  /// Cached bindable relation snapshots projected for arrow operations.
  ///
  /// The relation graph is derived from current arrow endpoint bindings and
  /// reused across interactive arrow sessions within the same document state.
  late final _arrowBindableRelations =
      List<core.BindableRelationState>.unmodifiable(
        collectCoreBindableRelations(elements),
      );

  /// Cached bindable anchor-id lookup used for stable reorder reductions.
  ///
  /// This includes bindable ids and any additional anchor element ids that
  /// should remain below bound arrows (for example serial-number labels).
  late final Map<String, List<String>> _arrowAnchorElementIdsByBindableId =
      collectCoreAnchorElementIdsByBindableId(elements);

  /// Cached highlight elements in document z-order.
  ///
  /// The list is computed lazily once per [DocumentState] instance and reused
  /// by highlight-mask rendering paths to avoid repeated O(n) scans during
  /// high-frequency interactions.
  late final highlightElements = List<ElementState>.unmodifiable(
    _buildHighlightElements(),
  );

  /// Arrow bindable projections for this document snapshot.
  List<core.BindableState> get arrowBindableStates => _arrowBindableStates;

  /// Arrow bindables keyed by element id.
  Map<String, core.BindableState> get arrowBindableStateById =>
      _arrowBindableStateById;

  /// Arrow bindable relation projections for this document snapshot.
  List<core.BindableRelationState> get arrowBindableRelations =>
      _arrowBindableRelations;

  /// Bindable id -> anchor element ids used by arrow reorder reductions.
  Map<String, List<String>> get arrowAnchorElementIdsByBindableId =>
      _arrowAnchorElementIdsByBindableId;

  Map<String, ElementState> get elementMap => _elementMap;

  ElementState? getElementById(String id) => _elementMap[id];

  int? getOrderIndex(String id) => _orderIndex[id];

  ElementState _elementForEntry(SpatialIndexEntry entry) =>
      _elementMap[entry.id]!;

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
      if (!visitor(_elementForEntry(entry))) {
        return;
      }
    }
  }

  /// Touch lazy caches eagerly to avoid stalls during interactive work.
  int warmCaches() =>
      _elementMap.length +
      _orderIndex.length +
      orderedElementIds.length +
      _spatialIndex.size +
      _arrowBindableSpatialIndex.size +
      _arrowBindableStates.length +
      _arrowBindableStateById.length +
      _arrowBindableRelations.length +
      _arrowAnchorElementIdsByBindableId.length +
      boundArrowTargetIds.length +
      highlightElements.length;

  /// Returns true when any element in [elementIds] has bound arrow endpoints.
  bool hasArrowBoundToAny(Iterable<String> elementIds) =>
      boundArrowTargetIds.isNotEmpty &&
      elementIds.any(boundArrowTargetIds.contains);

  bool hasElementAtPoint(DrawPoint point, double tolerance) => _spatialIndex
      .searchPointEntries(point, tolerance, sortByZ: false)
      .isNotEmpty;

  /// Queries elements intersecting [rect], sorted by ascending z-order.
  ///
  List<ElementState> queryElementsInRectOrdered(DrawRect rect) {
    final entries = _spatialIndex.searchRectEntries(rect, ascending: true);
    final result = <ElementState>[];
    for (final entry in entries) {
      result.add(_elementForEntry(entry));
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
    _visitEntries(_spatialIndex.searchPointEntries(point, tolerance), visitor);
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
    _visitEntries(
      _spatialIndex.searchPointEntries(point, tolerance, sortByZ: false),
      visitor,
    );
  }

  /// Visits rect-intersecting candidates in arbitrary order.
  ///
  /// This skips z-order sorting and is suitable for broad-phase queries where
  /// callers perform their own geometric checks.
  void visitElementsInRect(
    DrawRect rect,
    bool Function(ElementState element) visitor,
  ) {
    _visitEntries(
      _spatialIndex.searchRectEntries(rect, sortByZ: false),
      visitor,
    );
  }

  void _visitEntries(
    Iterable<SpatialIndexEntry> entries,
    bool Function(ElementState element) visitor,
  ) {
    for (final entry in entries) {
      if (!visitor(_elementForEntry(entry))) {
        return;
      }
    }
  }

  Set<String> _buildBoundTextIds() {
    final ids = <String>{};
    for (final element in elements) {
      if (element.data case SerialNumberData(:final textElementId?)) {
        ids.add(textElementId);
      }
    }
    return ids;
  }

  Set<String> _buildBoundArrowTargetIds() {
    final ids = <String>{};
    for (final element in elements) {
      final data = element.data;
      if (data is! ConnectorData) {
        continue;
      }
      _addBoundTargetId(ids, data.startBinding?.elementId);
      _addBoundTargetId(ids, data.endBinding?.elementId);
    }
    return ids;
  }

  List<ElementState> _buildArrowBindableElements() => [
    for (final element in elements)
      if (isArrowBindableElement(element)) element,
  ];

  List<ElementState> _buildHighlightElements() => [
    for (final element in elements)
      if (element.data is HighlightData) element,
  ];

  void _addBoundTargetId(Set<String> ids, String? targetId) {
    if (targetId == null) {
      return;
    }
    ids.add(targetId);
  }

  DocumentState copyWith({
    List<ElementState>? elements,
    int? elementsVersion,
    GlobalElementsState? globalElements,
  }) {
    final nextElements = elements ?? this.elements;
    final nextGlobalElements = globalElements ?? this.globalElements;
    final hasElementsChanged = !identical(nextElements, this.elements);
    final hasGlobalElementsChanged = nextGlobalElements != this.globalElements;
    final nextVersion =
        elementsVersion ??
        (hasElementsChanged || hasGlobalElementsChanged
            ? this.elementsVersion + 1
            : this.elementsVersion);

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
