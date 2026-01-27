import 'package:meta/meta.dart';

import '../edit/edit_operation_registry_interface.dart';
import '../edit/preview/edit_preview.dart';
import '../edit/preview/edit_preview_engine.dart';
import '../models/draw_state.dart';
import '../models/draw_state_view.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import '../types/snap_guides.dart';
import '../utils/selection_calculator.dart';
import 'selection_data_computer.dart';
import 'selection_geometry_resolver.dart';

/// Builds [DrawStateView] instances.
///
/// This centralizes edit preview computation so downstream utilities (hit test,
/// painters, etc.) only depend on the derived view instead of edit operations.
@immutable
class DrawStateViewBuilder {
  DrawStateViewBuilder({
    required this.editOperations,
    EditPreviewEngine? previewEngine,
  }) : _previewEngine = previewEngine ?? EditPreviewEngine();
  final EditOperationRegistry editOperations;
  final EditPreviewEngine _previewEngine;

  DrawStateView build(DrawState state) {
    final snapGuides = _resolveSnapGuides(state);
    final createPreview = _buildCreatePreview(state);
    if (createPreview != null) {
      return createPreview;
    }

    final textEditingPreview = _buildTextEditingPreview(state);
    if (textEditingPreview != null) {
      return textEditingPreview;
    }

    final preview = _previewEngine.build(
      state: state,
      editOperations: editOperations,
    );

    if (preview == EditPreview.none) {
      return DrawStateView.fromState(state, snapGuides: snapGuides);
    }

    final effectiveSelection = preview.selectionPreview != null
        ? EffectiveSelection(
            bounds: preview.selectionPreview!.bounds,
            center: preview.selectionPreview!.center,
            rotation: preview.selectionPreview!.rotation,
            hasSelection: true,
          )
        : _buildSelectionFromState(state);

    return DrawStateView.withPreview(
      state: state,
      previewElementsById: preview.previewElementsById,
      effectiveSelection: effectiveSelection,
      snapGuides: snapGuides,
    );
  }

  DrawStateView? _buildCreatePreview(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return null;
    }

    final element = interaction.element;
    if (element.rect == interaction.currentRect) {
      return null;
    }

    final previewElement = element.copyWith(rect: interaction.currentRect);
    return DrawStateView.withPreview(
      state: state,
      previewElementsById: {previewElement.id: previewElement},
      effectiveSelection: _buildSelectionFromState(state),
      snapGuides: interaction.snapGuides,
    );
  }

  DrawStateView? _buildTextEditingPreview(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return null;
    }

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
      final element = state.domain.document.getElementById(id);
      if (element != null) {
        selectedElements.add(element);
      }
    }

    if (selectedElements.isEmpty) {
      return EffectiveSelection.none;
    }

    final selectionBounds =
        SelectionCalculator.computeSelectionBoundsForElements(
          selectedElements,
        );
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
    if (!state.domain.hasSelection) {
      return EffectiveSelection.none;
    }

    final selection = SelectionDataComputer.compute(state);
    return EffectiveSelection(
      bounds: selection.overlayBounds,
      center: selection.overlayCenter,
      rotation: selection.overlayRotation,
      hasSelection: selection.hasSelection,
    );
  }

  static List<SnapGuide> _resolveSnapGuides(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is EditingState) {
      return interaction.snapGuides;
    }
    if (interaction is CreatingState) {
      return interaction.snapGuides;
    }
    return const [];
  }
}
