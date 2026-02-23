import 'package:meta/meta.dart';

import '../edit/edit_operation_registry_interface.dart';
import '../edit/preview/edit_preview_engine.dart';
import '../models/draw_state.dart';
import '../models/draw_state_view.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import 'text/text_metrics_service.dart';
import '../utils/selection_calculator.dart';
import 'selection_data_computer.dart';
import 'selection_geometry_resolver.dart';

/// Builds [DrawStateView] instances.
///
/// This centralizes edit preview computation so downstream utilities (hit test,
/// painters, etc.) only depend on the derived view instead of edit operations.
@immutable
class DrawStateViewBuilder {
  static const _sharedPreviewEngine = EditPreviewEngine();
  static final Expando<_DrawStateViewCacheEntry> _stateViewCache = Expando(
    'draw_state_view_cache',
  );

  const DrawStateViewBuilder({
    required this.editOperations,
    this.textMetricsService = defaultTextMetricsService,
    EditPreviewEngine? previewEngine,
  }) : _previewEngine = previewEngine ?? _sharedPreviewEngine;
  final EditOperationRegistry editOperations;
  final TextMetricsService textMetricsService;
  final EditPreviewEngine _previewEngine;

  DrawStateView build(DrawState state) {
    final cached = _stateViewCache[state];
    if (cached != null &&
        identical(cached.editOperations, editOperations) &&
        identical(cached.textMetricsService, textMetricsService) &&
        identical(cached.previewEngine, _previewEngine)) {
      return cached.view;
    }

    final nextView = _buildUncached(state);
    _stateViewCache[state] = _DrawStateViewCacheEntry(
      editOperations: editOperations,
      textMetricsService: textMetricsService,
      previewEngine: _previewEngine,
      view: nextView,
    );
    return nextView;
  }

  DrawStateView _buildUncached(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is CreatingState) {
      return DrawStateView.fromState(state, snapGuides: interaction.snapGuides);
    }

    if (interaction is TextEditingState) {
      return _buildTextEditingPreview(state: state, interaction: interaction);
    }

    if (interaction is! EditingState) {
      return DrawStateView.fromState(state);
    }

    final preview = _previewEngine.build(
      state: state,
      editOperations: editOperations,
      textMetricsService: textMetricsService,
    );
    final selectionPreview = preview.selectionPreview;
    final hasPreview =
        selectionPreview != null || preview.previewElementsById.isNotEmpty;
    if (!hasPreview) {
      return DrawStateView.fromState(state, snapGuides: interaction.snapGuides);
    }

    final effectiveSelection = selectionPreview != null
        ? EffectiveSelection(
            bounds: selectionPreview.bounds,
            center: selectionPreview.center,
            rotation: selectionPreview.rotation,
            hasSelection: true,
          )
        : _buildSelectionFromState(state);

    return DrawStateView.withPreview(
      state: state,
      previewElementsById: preview.previewElementsById,
      effectiveSelection: effectiveSelection,
      snapGuides: interaction.snapGuides,
    );
  }

  DrawStateView _buildTextEditingPreview({
    required DrawState state,
    required TextEditingState interaction,
  }) {
    final existingElement = state.domain.document.getElementById(
      interaction.elementId,
    );
    final previewElement = _buildTextEditingElement(
      state: state,
      interaction: interaction,
      element: existingElement,
    );

    return DrawStateView.withPreview(
      state: state,
      previewElementsById: {previewElement.id: previewElement},
      effectiveSelection: _buildSelectionWithPreview(
        state: state,
        previewElement: previewElement,
      ),
      snapGuides: const [],
    );
  }

  ElementState _buildTextEditingElement({
    required DrawState state,
    required TextEditingState interaction,
    required ElementState? element,
  }) {
    if (element == null) {
      return ElementState(
        id: interaction.elementId,
        rect: interaction.rect,
        rotation: interaction.rotation,
        opacity: interaction.opacity,
        zIndex: state.domain.document.elements.length,
        data: interaction.draftData,
      );
    }

    return element.copyWith(
      rect: interaction.rect,
      rotation: interaction.rotation,
      opacity: interaction.opacity,
      data: interaction.draftData,
    );
  }

  EffectiveSelection _buildSelectionWithPreview({
    required DrawState state,
    required ElementState previewElement,
  }) {
    final selection = state.domain.selection;
    if (!selection.hasSelection) {
      return EffectiveSelection.none;
    }

    final selectedElements = <ElementState>[
      for (final id in selection.selectedIds)
        if (id == previewElement.id)
          previewElement
        else
          ?state.domain.document.getElementById(id),
    ];

    if (selectedElements.isEmpty) {
      return EffectiveSelection.none;
    }

    final selectionBounds =
        SelectionCalculator.computeSelectionBoundsForElements(selectedElements);
    final geometry = SelectionGeometryResolver.resolve(
      selectedElements: selectedElements,
      selectionOverlay: state.application.selectionOverlay,
      selectionBounds: selectionBounds,
    );

    return EffectiveSelection(
      bounds: geometry.bounds,
      center: geometry.center,
      rotation: geometry.rotation,
      hasSelection: geometry.hasSelection,
    );
  }

  static EffectiveSelection _buildSelectionFromState(DrawState state) {
    final selection = SelectionDataComputer.compute(state);
    if (!selection.hasSelection) {
      return EffectiveSelection.none;
    }

    return EffectiveSelection(
      bounds: selection.overlayBounds,
      center: selection.overlayCenter,
      rotation: selection.overlayRotation,
      hasSelection: true,
    );
  }
}

@immutable
class _DrawStateViewCacheEntry {
  const _DrawStateViewCacheEntry({
    required this.editOperations,
    required this.textMetricsService,
    required this.previewEngine,
    required this.view,
  });

  final EditOperationRegistry editOperations;
  final TextMetricsService textMetricsService;
  final EditPreviewEngine previewEngine;
  final DrawStateView view;
}
