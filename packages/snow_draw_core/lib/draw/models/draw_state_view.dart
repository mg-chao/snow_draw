import 'package:meta/meta.dart';

import '../elements/types/highlight/highlight_data.dart';
import '../services/selection_data_computer.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/snap_guides.dart';
import 'element_state.dart';
import 'interaction_state.dart';
import 'models.dart' show DrawState;

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
  HighlightMaskSceneSnapshot(List<ElementState> elements)
    : _elements = List<ElementState>.unmodifiable(elements);

  final List<ElementState> _elements;

  /// Highlight elements in the order expected by highlight mask compositing.
  List<ElementState> get elements => _elements;

  /// Whether at least one highlight is present in this snapshot.
  bool get hasHighlights => _elements.isNotEmpty;
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
    return DrawStateView._(
      state: state,
      previewElementsById: const {},
      effectiveSelection: EffectiveSelection(
        bounds: selection.overlayBounds,
        center: selection.overlayCenter,
        rotation: selection.overlayRotation,
        hasSelection: state.domain.hasSelection,
      ),
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
    final highlights = <ElementState>[];

    for (final element in state.domain.document.elements) {
      final effective = effectiveElement(element);
      if (effective.data is HighlightData) {
        highlights.add(effective);
      }
    }

    if (_previewElementsById.isNotEmpty) {
      final document = state.domain.document;
      for (final preview in _previewElementsById.values) {
        if (document.getElementById(preview.id) != null) {
          continue;
        }
        if (preview.data is HighlightData) {
          highlights.add(preview);
        }
      }
    }

    final interaction = state.application.interaction;
    if (interaction is CreatingState &&
        interaction.elementData is HighlightData) {
      highlights.add(
        interaction.element.copyWith(rect: interaction.currentRect),
      );
    }

    return HighlightMaskSceneSnapshot(highlights);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawStateView &&
          other.state == state &&
          _mapsEqual(other._previewElementsById, _previewElementsById) &&
          other._effectiveSelection == _effectiveSelection &&
          _listEquals(other.snapGuides, snapGuides);

  @override
  int get hashCode => Object.hash(
    state,
    Object.hashAll(
      _previewElementsById.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    _effectiveSelection,
    Object.hashAll(snapGuides),
  );

  /// Helper to compare maps for equality.
  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  static bool _listEquals(List<SnapGuide> a, List<SnapGuide> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
