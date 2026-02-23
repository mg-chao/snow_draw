import '../../config/draw_config.dart';
import '../../elements/core/element_registry_interface.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state_view.dart';
import '../../models/element_state.dart';
import '../../types/element_style.dart';
import '../../types/draw_rect.dart';
import '../../utils/selection_calculator.dart';
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
    this.isHighlightMaskVisible = false,
    this.watermarkConfig,
    this.isWatermarkVisible = false,
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
  final bool isHighlightMaskVisible;
  final WatermarkConfig? watermarkConfig;
  final bool isWatermarkVisible;
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

    final highlightMaskConfig = transientState.highlightMaskConfig;
    if (highlightMaskConfig != null &&
        transientState.isHighlightMaskVisible &&
        view.highlightMaskScene.hasHighlights) {
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
    if (watermarkConfig != null && transientState.isWatermarkVisible) {
      tasks.add(WatermarkRenderTask(config: watermarkConfig));
    }

    final snapConfig = transientState.snapConfig;
    final snapGuides = view.snapGuides;
    if (snapConfig != null && snapGuides.isNotEmpty && snapConfig.showGuides) {
      tasks.add(
        SnapGuidesRenderTask(guides: snapGuides, snapConfig: snapConfig),
      );
    }

    final selectedIds = view.selectedIds;
    final selectedEffectiveElements = <ElementState>[
      for (final element in view.selectedElements)
        transientState.previewElementsById[element.id] ??
            view.effectiveElement(element),
    ];

    final hoverSelectionConfig = transientState.hoverSelectionConfig;
    final hoveredElementId = transientState.hoveredElementId;
    if (hoveredElementId != null &&
        hoverSelectionConfig != null &&
        !selectedIds.contains(hoveredElementId)) {
      final hovered = view.state.domain.document.getElementById(
        hoveredElementId,
      );
      if (hovered != null) {
        final effectiveHovered =
            transientState.previewElementsById[hovered.id] ??
            view.effectiveElement(hovered);
        tasks.add(
          HoverOutlineRenderTask(
            element: effectiveHovered,
            config: hoverSelectionConfig,
            useTextUnderlineStyle: effectiveHovered.data is TextData,
          ),
        );
      }
    }

    final effectiveSelection = view.effectiveSelection;
    final selectionConfig = transientState.selectionConfig;
    if (selectionConfig != null &&
        effectiveSelection.hasSelection &&
        effectiveSelection.bounds != null) {
      if (selectedIds.length > 1) {
        for (final selected in selectedEffectiveElements) {
          tasks.add(
            SelectionOutlineRenderTask(
              bounds: selected.rect,
              config: selectionConfig,
              rotation: selected.rotation,
              rotationCenter: selected.center,
              dashed: false,
            ),
          );
        }
      }

      final firstSelectedData = selectedEffectiveElements.isEmpty
          ? null
          : selectedEffectiveElements.first.data;
      final isSingleTwoPointArrow =
          selectedIds.length == 1 &&
          firstSelectedData is ArrowLikeData &&
          firstSelectedData.points.length == 2;
      final isSingleElbowArrow =
          selectedIds.length == 1 &&
          firstSelectedData is ArrowLikeData &&
          firstSelectedData.arrowType == ArrowType.elbow;
      final cornerHandleOffset =
          selectedIds.length == 1 && firstSelectedData is ArrowLikeData
          ? 8.0
          : 0.0;

      if (!isSingleTwoPointArrow) {
        final selectionBounds = effectiveSelection.bounds!;
        tasks.add(
          SelectionControlsRenderTask(
            bounds: selectionBounds,
            config: selectionConfig,
            rotation: effectiveSelection.rotation,
            rotationCenter: effectiveSelection.center ?? selectionBounds.center,
            dashed: selectedIds.length > 1,
            cornerHandleOffset: cornerHandleOffset,
            showRotationHandle: !isSingleElbowArrow,
          ),
        );
      }
    }

    if (selectionConfig != null && selectedIds.length == 1) {
      final selectedId = selectedIds.first;
      final selected = view.state.domain.document.getElementById(selectedId);
      if (selected != null) {
        final effectiveSelected =
            transientState.previewElementsById[selected.id] ??
            view.effectiveElement(selected);
        final data = effectiveSelected.data;
        if (data is ArrowLikeData) {
          final handleTolerance =
              selectionConfig.interaction.handleTolerance / effectiveScale;
          final loopThreshold = handleTolerance * 1.5;
          final baseHandleSize =
              selectionConfig.render.controlPointSize / effectiveScale;
          final handleSize =
              baseHandleSize * ConfigDefaults.arrowPointSizeMultiplier;
          final overlay = ArrowPointUtils.buildOverlay(
            element: effectiveSelected,
            loopThreshold: loopThreshold,
            handleSize: handleSize,
          );
          final handles = <ArrowPointHandle>[
            ...overlay.addablePoints,
            ...overlay.turningPoints,
            ...overlay.loopPoints,
          ];
          if (handles.isNotEmpty) {
            tasks.add(
              ArrowPointOverlayRenderTask(
                handles: List<ArrowPointHandle>.unmodifiable(handles),
                selectionConfig: selectionConfig,
                activeHandle: transientState.activeArrowHandle,
                hoveredHandle: transientState.hoveredArrowHandle,
                deleteIndicatorVisible:
                    transientState.arrowDeleteIndicatorVisible,
              ),
            );
          }
        }
      }
    }

    if (selectedIds.length == 1 && hoverSelectionConfig != null) {
      final selectedId = selectedIds.first;
      final selected = view.state.domain.document.getElementById(selectedId);
      if (selected != null) {
        final effectiveSelected =
            transientState.previewElementsById[selected.id] ??
            view.effectiveElement(selected);
        if (effectiveSelected.data is TextData) {
          tasks.add(
            SelectionOutlineRenderTask(
              bounds: effectiveSelected.rect,
              config: hoverSelectionConfig,
              rotation: effectiveSelected.rotation,
              rotationCenter: effectiveSelected.center,
            ),
          );
        }
      }
    }

    final boxSelectionBounds = transientState.boxSelectionBounds;
    final boxSelectionConfig = transientState.boxSelectionConfig;
    if (boxSelectionBounds != null && boxSelectionConfig != null) {
      final previewElements = <ElementState>[];
      for (final candidate in view.state.domain.document.getElementsInRect(
        boxSelectionBounds,
      )) {
        final effective =
            transientState.previewElementsById[candidate.id] ??
            view.effectiveElement(candidate);
        final aabb = SelectionCalculator.computeElementWorldAabb(effective);
        if (_rectsIntersect(boxSelectionBounds, aabb)) {
          previewElements.add(effective);
        }
      }
      tasks.add(
        BoxSelectionRenderTask(
          bounds: boxSelectionBounds,
          config: boxSelectionConfig,
          previewElements: List<ElementState>.unmodifiable(previewElements),
        ),
      );
    }

    return FrameRenderPlan(
      tasks: List<RenderTask>.unmodifiable(tasks),
      camera: camera,
      scaleFactor: effectiveScale,
      localeTag: localeTag,
    );
  }

  bool _rectsIntersect(DrawRect a, DrawRect b) =>
      a.minX <= b.maxX &&
      a.maxX >= b.minX &&
      a.minY <= b.maxY &&
      a.maxY >= b.minY;
}
