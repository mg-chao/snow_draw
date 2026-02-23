import '../../config/draw_config.dart';
import '../../edit/arrow/arrow_point_operation.dart';
import '../../elements/core/element_registry_interface.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state_view.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_rect.dart';
import '../../types/element_style.dart';
import '../../utils/arrow_binding_highlight.dart';
import '../../utils/binding_highlight_visibility.dart';
import '../../utils/selection_calculator.dart';
import '../planning/highlight_mask_visibility.dart';
import '../planning/watermark_visibility.dart';
import '../rect_intersection.dart';
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
    final previewElementsById = transientState.previewElementsById;

    ElementState resolveEffectiveElement(ElementState element) =>
        previewElementsById[element.id] ?? view.effectiveElement(element);

    ElementState? resolveEffectiveElementById(String id) {
      final element = view.state.domain.document.getElementById(id);
      if (element == null) {
        return null;
      }
      return resolveEffectiveElement(element);
    }

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
      final effectiveElement = resolveEffectiveElement(element);
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

    if (previewElementsById.isNotEmpty) {
      final previewOnlyElements = <ElementState>[];
      final document = view.state.domain.document;
      for (final entry in previewElementsById.entries) {
        if (document.getElementById(entry.key) != null) {
          continue;
        }
        previewOnlyElements.add(entry.value);
      }
      if (previewOnlyElements.isNotEmpty) {
        previewOnlyElements.sort((a, b) {
          final zIndexComparison = a.zIndex.compareTo(b.zIndex);
          if (zIndexComparison != 0) {
            return zIndexComparison;
          }
          return a.id.compareTo(b.id);
        });
        for (final previewElement in previewOnlyElements) {
          final definition = elementRegistry.getDefinitionByValue(
            previewElement.typeId.value,
          );
          if (definition == null) {
            continue;
          }
          tasks.addAll(
            definition.taskEncoder.encodeTasks(
              element: previewElement,
              localeTag: localeTag,
            ),
          );
        }
      }
    }

    final highlightMaskConfig = transientState.highlightMaskConfig;
    if (highlightMaskConfig != null &&
        isHighlightMaskVisible(
          hasHighlights: view.highlightMaskScene.hasHighlights,
          config: highlightMaskConfig,
        )) {
      tasks.add(
        HighlightMaskRenderTask(
          config: highlightMaskConfig,
          highlights: view.highlightMaskScene.elements,
        ),
      );
    }

    final watermarkConfig = transientState.watermarkConfig;
    if (watermarkConfig != null && isWatermarkVisible(watermarkConfig)) {
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
        resolveEffectiveElement(element),
    ];
    final singleSelectedElement = selectedIds.length == 1
        ? resolveEffectiveElementById(selectedIds.first)
        : null;

    final hoverSelectionConfig = transientState.hoverSelectionConfig;
    final hoveredElementId = transientState.hoveredElementId;
    if (hoveredElementId != null &&
        hoverSelectionConfig != null &&
        !selectedIds.contains(hoveredElementId)) {
      final effectiveHovered = resolveEffectiveElementById(hoveredElementId);
      if (effectiveHovered != null) {
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

    if (selectionConfig != null && singleSelectedElement != null) {
      final data = singleSelectedElement.data;
      if (data is ArrowLikeData) {
        final handleTolerance =
            selectionConfig.interaction.handleTolerance / effectiveScale;
        final loopThreshold = handleTolerance * 1.5;
        final baseHandleSize =
            selectionConfig.render.controlPointSize / effectiveScale;
        final handleSize =
            baseHandleSize * ConfigDefaults.arrowPointSizeMultiplier;
        final overlay = ArrowPointUtils.buildOverlay(
          element: singleSelectedElement,
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

    if (selectionConfig != null) {
      final highlightElementIds = _resolveArrowBindingHighlightElementIds(
        view: view,
        transientState: transientState,
      );
      if (highlightElementIds.isNotEmpty) {
        tasks.add(
          ArrowBindingHighlightRenderTask(
            elementIds: List<String>.unmodifiable(highlightElementIds),
            strokeColor: selectionConfig.render.strokeColor,
          ),
        );
      }
    }

    if (singleSelectedElement != null && hoverSelectionConfig != null) {
      if (singleSelectedElement.data is TextData) {
        tasks.add(
          SelectionOutlineRenderTask(
            bounds: singleSelectedElement.rect,
            config: hoverSelectionConfig,
            rotation: singleSelectedElement.rotation,
            rotationCenter: singleSelectedElement.center,
          ),
        );
      }
    }

    final boxSelectionBounds = transientState.boxSelectionBounds;
    final boxSelectionConfig = transientState.boxSelectionConfig;
    if (boxSelectionBounds != null &&
        boxSelectionConfig != null &&
        selectionConfig != null) {
      final previewElements = <ElementState>[];
      for (final candidate in view.state.domain.document.getElementsInRect(
        boxSelectionBounds,
      )) {
        final effective = resolveEffectiveElement(candidate);
        final aabb = SelectionCalculator.computeElementWorldAabb(effective);
        if (rectsIntersect(boxSelectionBounds, aabb)) {
          previewElements.add(effective);
        }
      }
      tasks.add(
        BoxSelectionRenderTask(
          bounds: boxSelectionBounds,
          config: boxSelectionConfig,
          selectionConfig: selectionConfig,
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

  List<String> _resolveArrowBindingHighlightElementIds({
    required DrawStateView view,
    required FrameRenderTransientState transientState,
  }) {
    final highlightElementIds = <String>{};
    _addHighlightElementId(
      highlightElementIds,
      resolveHoverBindingHighlightId(
        hoveredBindingElementId: transientState.hoveredBindingElementId,
        hoveredArrowHandle: transientState.hoveredArrowHandle,
      ),
    );

    final interaction = view.state.application.interaction;
    if (interaction is EditingState &&
        interaction.context is ArrowPointEditContext) {
      final context = interaction.context as ArrowPointEditContext;
      final element = view.state.domain.document.getElementById(
        context.elementId,
      );
      if (element == null) {
        return highlightElementIds.toList(growable: false);
      }

      final effectiveElement =
          transientState.previewElementsById[element.id] ??
          view.effectiveElement(element);
      final data = effectiveElement.data;
      if (data is ArrowLikeData) {
        final binding = resolveArrowPointEditHighlightBinding(
          context: context,
          data: data,
          transform: interaction.currentTransform,
        );
        _addHighlightElementId(highlightElementIds, binding?.elementId);
      }
      return highlightElementIds.toList(growable: false);
    }

    if (interaction is CreatingState && interaction.isPointCreation) {
      final data = interaction.element.data;
      if (data is ArrowLikeData) {
        _addHighlightElementId(
          highlightElementIds,
          data.startBinding?.elementId,
        );
        _addHighlightElementId(highlightElementIds, data.endBinding?.elementId);
      }
    }

    return highlightElementIds.toList(growable: false);
  }

  void _addHighlightElementId(Set<String> target, String? elementId) {
    if (elementId == null || elementId.isEmpty) {
      return;
    }
    target.add(elementId);
  }
}
