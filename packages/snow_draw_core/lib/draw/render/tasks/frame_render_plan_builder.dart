import '../../config/draw_config.dart';
import '../../edit/arrow/arrow_point_operation.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state_view.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_rect.dart';
import '../../utils/arrow_binding_highlight.dart';
import '../../utils/arrow_point_metrics.dart';
import '../../utils/binding_highlight_visibility.dart';
import '../../utils/camera_zoom.dart';
import '../../utils/selection_calculator.dart';
import '../../utils/single_selection_profile.dart';
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
    required double scaleFactor,
    String? localeTag,
    FrameRenderTransientState transientState =
        const FrameRenderTransientState(),
  }) {
    final tasks = <FrameRenderTask>[];
    final camera = view.state.application.view.camera;
    final effectiveScale = resolveEffectiveZoom(scaleFactor);
    final previewElementsById = transientState.previewElementsById;
    final document = view.state.domain.document;

    ElementState resolveEffectiveElement(ElementState element) =>
        previewElementsById[element.id] ?? view.effectiveElement(element);

    ElementState? resolveEffectiveElementById(String id) {
      final element = document.getElementById(id);
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
    final singleSelection = resolveSingleSelectionProfile(
      selectedIds: selectedIds,
      resolveElementById: resolveEffectiveElementById,
    );
    final singleSelectedElement = singleSelection.element;

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

      if (!singleSelection.isTwoPointArrow) {
        final selectionBounds = effectiveSelection.bounds!;
        tasks.add(
          SelectionControlsRenderTask(
            bounds: selectionBounds,
            config: selectionConfig,
            rotation: effectiveSelection.rotation,
            rotationCenter: effectiveSelection.center ?? selectionBounds.center,
            dashed: selectedIds.length > 1,
            cornerHandleOffset: singleSelection.cornerHandleOffset,
            showRotationHandle: !singleSelection.isElbowArrow,
          ),
        );
      }
    }

    if (selectionConfig != null && singleSelection.arrowData != null) {
      final handleTolerance =
          selectionConfig.interaction.handleTolerance / effectiveScale;
      final loopThreshold = resolveArrowPointLoopThreshold(handleTolerance);
      final baseHandleSize =
          selectionConfig.render.controlPointSize / effectiveScale;
      final handleSize = resolveArrowPointHandleSize(baseHandleSize);
      final overlay = ArrowPointUtils.buildOverlay(
        element: singleSelectedElement!,
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
            deleteIndicatorVisible: transientState.arrowDeleteIndicatorVisible,
          ),
        );
      }
    }

    if (selectionConfig != null) {
      final highlightElementIds = _resolveArrowBindingHighlightElementIds(
        view: view,
        transientState: transientState,
        resolveEffectiveElement: resolveEffectiveElement,
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

    if (singleSelectedElement != null &&
        hoverSelectionConfig != null &&
        singleSelection.isText) {
      tasks.add(
        SelectionOutlineRenderTask(
          bounds: singleSelectedElement.rect,
          config: hoverSelectionConfig,
          rotation: singleSelectedElement.rotation,
          rotationCenter: singleSelectedElement.center,
        ),
      );
    }

    final boxSelectionBounds = transientState.boxSelectionBounds;
    final boxSelectionConfig = transientState.boxSelectionConfig;
    if (boxSelectionBounds != null &&
        boxSelectionConfig != null &&
        selectionConfig != null) {
      final previewElements = <ElementState>[];
      document.visitElementsInRect(boxSelectionBounds, (candidate) {
        final effective = resolveEffectiveElement(candidate);
        final aabb = SelectionCalculator.computeElementWorldAabb(effective);
        if (rectsIntersect(boxSelectionBounds, aabb)) {
          previewElements.add(effective);
        }
        return true;
      });
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
      tasks: List<FrameRenderTask>.unmodifiable(tasks),
      camera: camera,
      scaleFactor: effectiveScale,
      localeTag: localeTag,
    );
  }

  List<String> _resolveArrowBindingHighlightElementIds({
    required DrawStateView view,
    required FrameRenderTransientState transientState,
    required ElementState Function(ElementState element)
    resolveEffectiveElement,
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
      if (element != null) {
        final effectiveElement = resolveEffectiveElement(element);
        final data = effectiveElement.data;
        if (data is ArrowLikeData) {
          final binding = resolveArrowPointEditHighlightBinding(
            context: context,
            data: data,
            transform: interaction.currentTransform,
          );
          _addHighlightElementId(highlightElementIds, binding?.elementId);
        }
      }
    } else if (interaction is CreatingState && interaction.isPointCreation) {
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
