import 'package:meta/meta.dart';

import '../edit/edit_operations.dart';
import '../edit/preview/edit_preview_engine.dart';
import '../models/draw_state.dart';
import '../models/draw_state_view.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
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

  const DrawStateViewBuilder({
    required this.editOperations,
    EditPreviewEngine? previewEngine,
  }) : _previewEngine = previewEngine ?? _sharedPreviewEngine;
  final DefaultEditOperationRegistry editOperations;
  final EditPreviewEngine _previewEngine;

  DrawStateView build(DrawState state) => _buildUncached(state);

  DrawStateView _buildUncached(DrawState state) {
    final interaction = state.application.interaction;
    return switch (interaction) {
      final CreatingState creating => DrawStateView.fromState(
        state,
        snapGuides: creating.snapGuides,
      ),
      final TextEditingState textEditing => _buildTextEditingPreview(
        state: state,
        interaction: textEditing,
      ),
      final EditingState editing => _buildEditingPreview(
        state: state,
        interaction: editing,
      ),
      _ => DrawStateView.fromState(state),
    };
  }

  DrawStateView _buildEditingPreview({
    required DrawState state,
    required EditingState interaction,
  }) {
    final preview = _previewEngine.build(
      state: state,
      editOperations: editOperations,
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

    final selectedElements = <ElementState>[];
    for (final id in selection.selectedIds) {
      if (id == previewElement.id) {
        selectedElements.add(previewElement);
        continue;
      }
      final selectedElement = state.domain.document.getElementById(id);
      if (selectedElement != null) {
        selectedElements.add(selectedElement);
      }
    }

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
