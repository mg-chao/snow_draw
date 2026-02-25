import 'package:meta/meta.dart';

import '../elements/types/highlight/highlight_data.dart';
import '../services/selection_data_computer.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/snap_guides.dart';
import '../utils/list_equality.dart';
import 'document_state.dart';
import 'draw_state.dart';
import 'element_state.dart';
import 'global_elements_state.dart';
import 'interaction_state.dart';

/// Effective selection view (considering edit preview).
///
/// During an edit session, the persistent `DrawState.selection` remains, while
/// overlay geometry (bounds/center/rotation) may be overridden by the edit
/// preview. This type provides a unified view for hit-testing and rendering.
@immutable
class EffectiveSelection {
  const EffectiveSelection({
    this.bounds,
    this.center,
    this.rotation,
    this.hasSelection = false,
  });
  final DrawRect? bounds;
  final DrawPoint? center;
  final double? rotation;
  final bool hasSelection;

  static const none = EffectiveSelection();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectiveSelection &&
          other.bounds == bounds &&
          other.center == center &&
          other.rotation == rotation &&
          other.hasSelection == hasSelection;

  @override
  int get hashCode => Object.hash(bounds, center, rotation, hasSelection);
}

/// Precomputed highlight elements used by highlight mask rendering.
///
/// This snapshot is derived from the current state view and preserves the
/// painter ordering semantics: document/effective elements first, preview-only
/// transient elements next, then the in-progress creating element last.
@immutable
class HighlightMaskSceneSnapshot {
  HighlightMaskSceneSnapshot({required List<ElementState> elements})
    : _elements = List<ElementState>.unmodifiable(elements);

  final List<ElementState> _elements;

  /// Highlight elements in the order expected by highlight mask compositing.
  List<ElementState> get elements => _elements;

  /// Whether at least one highlight is present in this snapshot.
  bool get hasHighlights => _elements.isNotEmpty;

  /// Reusable empty snapshot.
  static final empty = HighlightMaskSceneSnapshot(elements: const []);
}

/// A unified "effective state" view for rendering and hit-testing.
///
/// In the preview/commit architecture:
/// - Persistent state lives in `DrawState` (elements/selection/camera...)
/// - In-progress edit deltas live in `DrawState.interaction`
/// - Rendering and hit-testing should use the effective preview values without
///   needing to know how to build them.
@immutable
class DrawStateView {
  DrawStateView._({
    required this.state,
    required Map<String, ElementState> previewElementsById,
    required EffectiveSelection effectiveSelection,
    required this.snapGuides,
  }) : _previewElementsById = previewElementsById,
       _effectiveSelection = effectiveSelection;

  /// Creates a view directly from state (no edit preview).
  factory DrawStateView.fromState(
    DrawState state, {
    List<SnapGuide> snapGuides = const [],
  }) {
    final selection = SelectionDataComputer.compute(state);
    final effectiveSelection = selection.hasSelection
        ? EffectiveSelection(
            bounds: selection.overlayBounds,
            center: selection.overlayCenter,
            rotation: selection.overlayRotation,
            hasSelection: selection.hasSelection,
          )
        : EffectiveSelection.none;

    return DrawStateView._(
      state: state,
      previewElementsById: const {},
      effectiveSelection: effectiveSelection,
      snapGuides: snapGuides,
    );
  }

  /// Creates a view from state plus preview-derived values.
  factory DrawStateView.withPreview({
    required DrawState state,
    required Map<String, ElementState> previewElementsById,
    required EffectiveSelection effectiveSelection,
    required List<SnapGuide> snapGuides,
  }) => DrawStateView._(
    state: state,
    previewElementsById: previewElementsById,
    effectiveSelection: effectiveSelection,
    snapGuides: snapGuides,
  );

  /// Underlying persistent state.
  final DrawState state;

  final Map<String, ElementState> _previewElementsById;
  final EffectiveSelection _effectiveSelection;
  final List<SnapGuide> snapGuides;

  /// Cached highlight scene payload for mask rendering.
  ///
  /// This is computed lazily once per [DrawStateView] instance.
  late final HighlightMaskSceneSnapshot highlightMaskScene =
      _buildHighlightMaskScene();

  /// Map of element IDs to their preview states.
  Map<String, ElementState> get previewElementsById => _previewElementsById;

  /// IDs of elements currently being previewed.
  Set<String> get previewElementIds => _previewElementsById.keys.toSet();

  /// Returns the effective (preview) element for the provided `element`.
  ///
  /// If no preview exists for that id, returns `element`.
  ElementState effectiveElement(ElementState element) =>
      _previewElementsById[element.id] ?? element;

  /// Effective selection overlay values.
  EffectiveSelection get effectiveSelection => _effectiveSelection;

  /// All elements in their persistent order.
  List<ElementState> get elements => state.domain.document.elements;

  /// Selected ids.
  Set<String> get selectedIds => state.domain.selection.selectedIds;

  /// Effective global document elements.
  GlobalElementsState get globalElements =>
      state.domain.document.globalElements;

  /// True if there is an active selection (either persistent or preview).
  bool get hasSelection => _effectiveSelection.hasSelection;

  /// Selected elements in render (z) order.
  ///
  /// This preserves the ordering from `DrawState.elements` so callers can
  /// render outlines consistently.
  Iterable<ElementState> get selectedElements {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    return state.domain.document.elements.where(
      (e) => selectedIds.contains(e.id),
    );
  }

  HighlightMaskSceneSnapshot _buildHighlightMaskScene() {
    final document = state.domain.document;
    final previewElementsById = _previewElementsById;
    final creatingHighlight = _resolveCreatingHighlightElement();
    if (creatingHighlight == null && previewElementsById.isEmpty) {
      return _snapshotForHighlights(document.highlightElements);
    }

    final highlights = <ElementState>[];
    final includedIds = <String>{};
    final creatingHighlightId = creatingHighlight?.id;

    for (final highlight in document.highlightElements) {
      final effective = highlight.id == creatingHighlightId
          ? creatingHighlight
          : previewElementsById[highlight.id] ?? highlight;
      _appendIfHighlight(
        target: highlights,
        includedIds: includedIds,
        element: effective,
      );
    }

    for (final preview in previewElementsById.values) {
      if (_isPreviewCoveredByDocumentHighlight(
        preview: preview,
        creatingHighlightId: creatingHighlightId,
        includedIds: includedIds,
        document: document,
      )) {
        continue;
      }
      _appendIfHighlight(
        target: highlights,
        includedIds: includedIds,
        element: preview,
      );
    }

    _appendIfHighlight(
      target: highlights,
      includedIds: includedIds,
      element: creatingHighlight,
    );

    return _snapshotForHighlights(highlights);
  }

  ElementState? _resolveCreatingHighlightElement() {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState ||
        interaction.elementData is! HighlightData) {
      return null;
    }
    return interaction.element.copyWith(rect: interaction.currentRect);
  }

  bool _isPreviewCoveredByDocumentHighlight({
    required ElementState preview,
    required String? creatingHighlightId,
    required Set<String> includedIds,
    required DocumentState document,
  }) =>
      preview.id == creatingHighlightId ||
      includedIds.contains(preview.id) ||
      document.getElementById(preview.id)?.data is HighlightData;

  void _appendIfHighlight({
    required List<ElementState> target,
    required Set<String> includedIds,
    required ElementState? element,
  }) {
    if (element == null ||
        element.data is! HighlightData ||
        !includedIds.add(element.id)) {
      return;
    }
    target.add(element);
  }

  HighlightMaskSceneSnapshot _snapshotForHighlights(List<ElementState> values) {
    if (values.isEmpty) {
      return HighlightMaskSceneSnapshot.empty;
    }
    return HighlightMaskSceneSnapshot(elements: values);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawStateView &&
          other.state == state &&
          mapEquals(other._previewElementsById, _previewElementsById) &&
          other._effectiveSelection == _effectiveSelection &&
          snapGuideListEquals(other.snapGuides, snapGuides);

  @override
  int get hashCode => Object.hash(
    state,
    mapHash(_previewElementsById),
    _effectiveSelection,
    listHash(snapGuides),
  );
}
