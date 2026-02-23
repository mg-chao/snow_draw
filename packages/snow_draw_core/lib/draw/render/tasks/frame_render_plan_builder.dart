import '../../config/draw_config.dart';
import '../../elements/core/element_registry_interface.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../models/draw_state_view.dart';
import '../../models/element_state.dart';
import '../../types/draw_rect.dart';
import 'frame_render_plan.dart';
import 'render_tasks.dart';

/// Transient UI-facing inputs that are not persisted in [DrawStateView].
class FrameRenderTransientState {
  const FrameRenderTransientState({
    this.hoveredElementId,
    this.hoveredBindingElementId,
    this.hoveredArrowHandle,
    this.activeArrowHandle,
    this.arrowDeleteIndicatorVisible = false,
    this.selectionConfig,
    this.hoverSelectionConfig,
    this.boxSelectionConfig,
    this.snapConfig,
    this.canvasConfig,
    this.gridConfig,
    this.highlightMaskConfig,
    this.watermarkConfig,
    this.boxSelectionBounds,
    this.previewElementsById = const <String, ElementState>{},
  });

  final String? hoveredElementId;
  final String? hoveredBindingElementId;
  final ArrowPointHandle? hoveredArrowHandle;
  final ArrowPointHandle? activeArrowHandle;
  final bool arrowDeleteIndicatorVisible;
  final SelectionConfig? selectionConfig;
  final SelectionConfig? hoverSelectionConfig;
  final BoxSelectionConfig? boxSelectionConfig;
  final SnapConfig? snapConfig;
  final CanvasConfig? canvasConfig;
  final GridConfig? gridConfig;
  final HighlightMaskConfig? highlightMaskConfig;
  final WatermarkConfig? watermarkConfig;
  final DrawRect? boxSelectionBounds;
  final Map<String, ElementState> previewElementsById;
}

/// Builds deterministic frame render plans from [DrawStateView].
class FrameRenderPlanBuilder {
  const FrameRenderPlanBuilder();

  /// Builds a frame plan for the current state.
  FrameRenderPlan build({
    required DrawStateView view,
    required ElementRegistry elementRegistry,
    required double scaleFactor,
    String? localeTag,
    FrameRenderTransientState transientState =
        const FrameRenderTransientState(),
  }) {
    final tasks = <RenderTask>[];
    final camera = view.state.application.view.camera;
    final effectiveScale = scaleFactor == 0 ? 1.0 : scaleFactor;

    final canvasConfig = transientState.canvasConfig;
    if (canvasConfig != null) {
      tasks.add(BackgroundRenderTask(color: canvasConfig.backgroundColor));
    }

    final gridConfig = transientState.gridConfig;
    if (gridConfig != null) {
      tasks.add(
        GridRenderTask(
          enabled: gridConfig.enabled,
          size: gridConfig.size,
          lineWidth: gridConfig.lineWidth,
          lineColor: gridConfig.lineColor,
          lineOpacity: gridConfig.lineOpacity,
          majorLineEvery: gridConfig.majorLineEvery,
          majorLineOpacity: gridConfig.majorLineOpacity,
          minScreenSpacing: gridConfig.minScreenSpacing,
          minRenderSpacing: gridConfig.minRenderSpacing,
        ),
      );
    }

    for (final element in view.elements) {
      final effectiveElement =
          transientState.previewElementsById[element.id] ??
          view.effectiveElement(element);
      final definition = elementRegistry.getDefinitionByValue(
        effectiveElement.typeId.value,
      );
      if (definition == null) {
        continue;
      }
      tasks.addAll(
        definition.taskEncoder.encodeTasks(
          element: effectiveElement,
          localeTag: localeTag,
        ),
      );
    }

    final snapConfig = transientState.snapConfig;
    final snapGuides = view.snapGuides;
    if (snapConfig != null && snapGuides.isNotEmpty && snapConfig.showGuides) {
      tasks.add(
        SnapGuidesRenderTask(guides: snapGuides, snapConfig: snapConfig),
      );
    }

    final effectiveSelection = view.effectiveSelection;
    final selectionConfig = transientState.selectionConfig;
    if (selectionConfig != null &&
        effectiveSelection.hasSelection &&
        effectiveSelection.bounds != null) {
      tasks.add(
        SelectionControlsRenderTask(
          bounds: effectiveSelection.bounds!,
          config: selectionConfig,
          rotation: effectiveSelection.rotation,
          rotationCenter: effectiveSelection.center,
        ),
      );
    }

    final boxSelectionBounds = transientState.boxSelectionBounds;
    final boxSelectionConfig = transientState.boxSelectionConfig;
    if (boxSelectionBounds != null && boxSelectionConfig != null) {
      tasks.add(
        BoxSelectionRenderTask(
          bounds: boxSelectionBounds,
          config: boxSelectionConfig,
        ),
      );
    }

    final highlightMaskConfig = transientState.highlightMaskConfig;
    if (highlightMaskConfig != null && view.highlightMaskScene.hasHighlights) {
      tasks.add(
        HighlightMaskRenderTask(
          config: highlightMaskConfig,
          highlights: view.highlightMaskScene.elements,
          staticHighlights: view.highlightMaskScene.staticElements,
          dynamicHighlights: view.highlightMaskScene.dynamicElements,
        ),
      );
    }

    final watermarkConfig = transientState.watermarkConfig;
    if (watermarkConfig != null) {
      tasks.add(WatermarkRenderTask(config: watermarkConfig));
    }

    return FrameRenderPlan(
      tasks: List<RenderTask>.unmodifiable(tasks),
      camera: camera,
      scaleFactor: effectiveScale,
      localeTag: localeTag,
    );
  }
}
