import 'package:meta/meta.dart';

import '../elements/types/highlight/highlight_data.dart';
import '../services/selection_data_computer.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/snap_guides.dart';
import 'document_state.dart';
import 'element_state.dart';
import 'global_elements_state.dart';
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
  HighlightMaskSceneSnapshot({
    required List<ElementState> elements,
    required List<ElementState> staticElements,
    required List<ElementState> dynamicElements,
  }) : _elements = List<ElementState>.unmodifiable(elements),
       _staticElements = List<ElementState>.unmodifiable(staticElements),
       _dynamicElements = List<ElementState>.unmodifiable(dynamicElements);

  final List<ElementState> _elements;
  final List<ElementState> _staticElements;
  final List<ElementState> _dynamicElements;

  /// Highlight elements in the order expected by highlight mask compositing.
  List<ElementState> get elements => _elements;

  /// Stable highlights that do not change on every interaction frame.
  List<ElementState> get staticElements => _staticElements;

  /// Highlights whose geometry/style can change on the current frame.
  List<ElementState> get dynamicElements => _dynamicElements;

  /// Whether at least one highlight is present in this snapshot.
  bool get hasHighlights => _elements.isNotEmpty;

  /// Whether any highlight is dynamic for the active interaction.
  bool get hasDynamicHighlights => _dynamicElements.isNotEmpty;

  /// Reusable empty snapshot.
  static final empty = HighlightMaskSceneSnapshot(
    elements: const [],
    staticElements: const [],
    dynamicElements: const [],
  );
}

/// Lightweight metadata for highlight-mask routing decisions.
///
/// This summary intentionally avoids materializing full highlight element lists
/// so callers can decide whether to render the mask without paying for the
/// heavier scene snapshot on every frame.
@immutable
class HighlightMaskSceneSummary {
  const HighlightMaskSceneSummary({
    required this.hasHighlights,
    required this.hasDynamicHighlights,
  });

  /// Whether at least one highlight is present in the effective scene.
  final bool hasHighlights;

  /// Whether at least one highlight can change this frame.
  final bool hasDynamicHighlights;
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
    if (!state.domain.selection.hasSelection) {
      return DrawStateView._(
        state: state,
        previewElementsById: const {},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: snapGuides,
      );
    }

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

  /// Lightweight highlight-scene metadata.
  ///
  /// Use this summary for layer routing decisions when full highlight element
  /// lists are not required.
  late final HighlightMaskSceneSummary highlightMaskSceneSummary =
      _buildHighlightMaskSceneSummary();

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
    final summary = highlightMaskSceneSummary;
    if (!summary.hasHighlights) {
      return HighlightMaskSceneSnapshot.empty;
    }

    final document = state.domain.document;
    if (!summary.hasDynamicHighlights &&
        !_hasPreviewHighlightRemoval(document)) {
      final highlights = document.highlightElements;
      if (highlights.isEmpty) {
        return HighlightMaskSceneSnapshot.empty;
      }
      return HighlightMaskSceneSnapshot(
        elements: highlights,
        staticElements: highlights,
        dynamicElements: const [],
      );
    }

    final creatingHighlight = _resolveCreatingHighlightElement();
    final creatingHighlightId = creatingHighlight?.id;
    final dynamicHighlightIds = _resolveDynamicHighlightIds(document);
    final highlights = <ElementState>[];
    final staticHighlights = <ElementState>[];
    final dynamicHighlights = <ElementState>[];
    var includedCreatingHighlight = false;

    for (final element in document.highlightElements) {
      final isCreatingReplacement =
          creatingHighlightId != null && element.id == creatingHighlightId;
      final effective = isCreatingReplacement
          ? creatingHighlight!
          : (_previewElementsById[element.id] ?? element);
      if (effective.data is HighlightData) {
        if (isCreatingReplacement) {
          includedCreatingHighlight = true;
        }
        highlights.add(effective);
        if (dynamicHighlightIds.contains(effective.id)) {
          dynamicHighlights.add(effective);
        } else {
          staticHighlights.add(effective);
        }
      }
    }

    if (_previewElementsById.isNotEmpty) {
      for (final preview in _previewElementsById.values) {
        if (document.getElementById(preview.id) != null) {
          continue;
        }
        if (creatingHighlightId != null && preview.id == creatingHighlightId) {
          continue;
        }
        if (preview.data is HighlightData) {
          highlights.add(preview);
          dynamicHighlights.add(preview);
        }
      }
    }

    if (creatingHighlight != null && !includedCreatingHighlight) {
      highlights.add(creatingHighlight);
      dynamicHighlights.add(creatingHighlight);
    }

    return HighlightMaskSceneSnapshot(
      elements: highlights,
      staticElements: staticHighlights,
      dynamicElements: dynamicHighlights,
    );
  }

  HighlightMaskSceneSummary _buildHighlightMaskSceneSummary() {
    final document = state.domain.document;
    var remainingDocumentHighlightCount = document.highlightElements.length;
    var hasDynamicHighlights = false;
    var previewAddsHighlight = false;

    if (_previewElementsById.isNotEmpty) {
      for (final entry in _previewElementsById.entries) {
        final persisted = document.getElementById(entry.key);
        final preview = entry.value;
        final persistedIsHighlight = persisted?.data is HighlightData;
        final previewIsHighlight = preview.data is HighlightData;

        if (persistedIsHighlight && !previewIsHighlight) {
          remainingDocumentHighlightCount -= 1;
          continue;
        }

        if (!previewIsHighlight) {
          continue;
        }

        if (!persistedIsHighlight) {
          previewAddsHighlight = true;
        }
        if (persisted == null || persisted != preview) {
          hasDynamicHighlights = true;
        }
      }
    }

    var hasHighlights =
        remainingDocumentHighlightCount > 0 || previewAddsHighlight;
    if (_resolveCreatingHighlightElement() != null) {
      hasHighlights = true;
      hasDynamicHighlights = true;
    }

    return HighlightMaskSceneSummary(
      hasHighlights: hasHighlights,
      hasDynamicHighlights: hasDynamicHighlights,
    );
  }

  ElementState? _resolveCreatingHighlightElement() {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState ||
        interaction.elementData is! HighlightData) {
      return null;
    }
    return interaction.element.copyWith(rect: interaction.currentRect);
  }

  bool _hasPreviewHighlightRemoval(DocumentState document) {
    if (_previewElementsById.isEmpty) {
      return false;
    }
    for (final entry in _previewElementsById.entries) {
      final persisted = document.getElementById(entry.key);
      if (persisted?.data is HighlightData &&
          entry.value.data is! HighlightData) {
        return true;
      }
    }
    return false;
  }

  Set<String> _resolveDynamicHighlightIds(DocumentState document) {
    final ids = <String>{};
    if (_previewElementsById.isNotEmpty) {
      for (final entry in _previewElementsById.entries) {
        final preview = entry.value;
        if (preview.data is! HighlightData) {
          continue;
        }
        final persisted = document.getElementById(entry.key);
        if (persisted == null || persisted != preview) {
          ids.add(entry.key);
        }
      }
    }

    final interaction = state.application.interaction;
    if (interaction is CreatingState &&
        interaction.elementData is HighlightData) {
      ids.add(interaction.elementId);
    }
    return ids;
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
