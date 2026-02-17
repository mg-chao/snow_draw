import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextLayoutMetrics;

import '../../draw/actions/actions.dart';
import '../../draw/config/draw_config.dart';
import '../../draw/core/coordinates/element_space.dart';
import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/elements/core/element_data.dart';
import '../../draw/elements/core/element_hit_tester.dart';
import '../../draw/elements/core/element_type_id.dart';
import '../../draw/elements/text_rendering_cache_invalidation.dart';
import '../../draw/elements/types/arrow/arrow_binding.dart';
import '../../draw/elements/types/arrow/arrow_data.dart';
import '../../draw/elements/types/arrow/arrow_geometry.dart';
import '../../draw/elements/types/arrow/arrow_like_data.dart';
import '../../draw/elements/types/arrow/arrow_points.dart';
import '../../draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/elements/types/rectangle/rectangle_data.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/elements/types/text/text_layout.dart';
import '../../draw/input/input_event.dart';
import '../../draw/input/plugin_system.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/services/coordinate_service.dart';
import '../../draw/services/draw_state_view_builder.dart';
import '../../draw/store/draw_store_interface.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/edit_transform.dart';
import '../../draw/types/element_style.dart';
import '../../draw/utils/hit_test.dart' as draw_hit_test;
import '../../draw/utils/snapping_mode.dart';
import 'cursor_resolver.dart';
import 'dynamic_canvas_painter.dart';
import 'dynamic_layer_split.dart';
import 'dynamic_scene_optimization.dart';
import 'filter_shader_manager.dart';
import 'frame_aligned_pointer_move_dispatcher.dart';
import 'grid_shader_painter.dart';
import 'highlight_mask_shader_manager.dart';
import 'highlight_mask_visibility.dart';
import 'rectangle_shader_manager.dart';
import 'render_keys.dart';
import 'static_canvas_painter.dart';
import 'watermark_canvas_painter.dart';

/// DrawCanvas based on the plugin system.
///
/// This is the new-architecture DrawCanvas that handles input via plugins.
class PluginDrawCanvas extends StatefulWidget {
  const PluginDrawCanvas({
    required this.size,
    required this.store,
    super.key,
    this.scaleFactor = 1.0,
    this.currentToolTypeId,
    this.isSelectionToolActive = true,
    this.isEraserToolActive = false,
    this.middlewares,
    this.customPlugins,
    this.enableDebugLogging = false,
    this.enablePerformanceMonitoring = false,
  });
  final Size size;
  final double scaleFactor;
  final DrawStore store;
  final ElementTypeId<ElementData>? currentToolTypeId;
  final bool isSelectionToolActive;
  final bool isEraserToolActive;

  /// Custom middleware (optional).
  final List<InputMiddleware>? middlewares;

  /// Custom plugins (optional, appended after standard plugins).
  final List<InputPlugin>? customPlugins;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// Whether to enable performance monitoring.
  final bool enablePerformanceMonitoring;

  @override
  State<PluginDrawCanvas> createState() => _PluginDrawCanvasState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DoubleProperty('scaleFactor', scaleFactor))
      ..add(DiagnosticsProperty<DrawStore>('store', store))
      ..add(
        DiagnosticsProperty<ElementTypeId<ElementData>?>(
          'currentToolTypeId',
          currentToolTypeId,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'isSelectionToolActive',
          isSelectionToolActive,
        ),
      )
      ..add(DiagnosticsProperty<bool>('isEraserToolActive', isEraserToolActive))
      ..add(IterableProperty<InputMiddleware>('middlewares', middlewares))
      ..add(IterableProperty<InputPlugin>('customPlugins', customPlugins))
      ..add(DiagnosticsProperty<bool>('enableDebugLogging', enableDebugLogging))
      ..add(
        DiagnosticsProperty<bool>(
          'enablePerformanceMonitoring',
          enablePerformanceMonitoring,
        ),
      );
  }
}

class _EraserMoveEvent {
  const _EraserMoveEvent({required this.pointerId, required this.position});

  final int pointerId;
  final DrawPoint position;
}

class _HoverFrameEvent {
  const _HoverFrameEvent({
    required this.position,
    required this.modifiers,
    required this.dispatchPluginHover,
  });

  final DrawPoint position;
  final KeyModifiers modifiers;
  final bool dispatchPluginHover;

  _HoverFrameEvent mergeWith(_HoverFrameEvent incoming) => _HoverFrameEvent(
    position: incoming.position,
    modifiers: incoming.modifiers,
    dispatchPluginHover: dispatchPluginHover || incoming.dispatchPluginHover,
  );
}

class _PluginDrawCanvasState extends State<PluginDrawCanvas> {
  static const double _textSelectionPaddingBoost = 16;
  static const _strokeWidthSteps = [2.0, 4.0, 7.0];
  static const _fontSizeSteps = [16.0, 21.0, 27.0, 42.0];
  static const _eraserPreviewOpacityFactor = 0.5;
  static const _eraserCursorRadius = 8.0;
  static const _eraserCursorBorderWidth = 1.5;
  static const ValueKey<String> _eraserCursorOverlayKey = ValueKey(
    'eraser-cursor-overlay',
  );
  static const MouseCursor _defaultCursor = SystemMouseCursors.precise;
  static const MouseCursor _draggingCursor = SystemMouseCursors.grabbing;
  static const Set<DrawStateChange> _stateChangeTypes = {
    DrawStateChange.document,
    DrawStateChange.selection,
    DrawStateChange.view,
    DrawStateChange.interaction,
  };

  VoidCallback? _stateUnsubscribe;
  StreamSubscription<DrawConfig>? _configSubscription;
  final _focusNode = FocusNode();
  late final FocusNode _textFocusNode;
  TextEditingController? _textController;
  String? _editingElementId;
  var _suppressTextControllerChange = false;
  var _initialSelectionApplied = false;
  var _textFocusScheduled = false;
  TextLayoutMetrics? _editingTextLayout;
  PainterTextLayoutMetrics? _editingPainterLayout;
  _EditingPainterLayoutKey? _editingPainterLayoutKey;
  TextSelection? _lastVerticalSelection;
  double? _verticalCaretX;
  final _cursorResolver = const CursorResolver();
  final _cursorNotifier = ValueNotifier<MouseCursor>(_defaultCursor);

  var _isShiftPressed = false;
  var _isControlPressed = false;
  var _isAltPressed = false;

  var _isPointerInside = false;
  MouseCursor _cursor = _defaultCursor;
  DrawPoint? _lastPointerPosition;
  String? _hoveredSelectionElementId;
  String? _hoveredBindingElementId;
  ArrowPointHandle? _hoveredArrowHandle;
  final _activePointerIds = <int>{};
  final _eraserPointerIds = <int>{};
  final _pendingErasePreviewElementsById = <String, ElementState>{};
  final _lastEraserProcessedPositions = <int, DrawPoint>{};
  final _eraserHitTesterByType =
      <ElementTypeId<ElementData>, ElementHitTester?>{};
  final _eraserCursorPositionNotifier = ValueNotifier<DrawPoint?>(null);
  int? _middlePanPointerId;
  Offset? _lastMiddlePanPosition;

  CoordinateService? _coordinateService;
  late PluginInputCoordinator _pluginCoordinator;
  late DrawStateViewBuilder _stateViewBuilder;
  late final WatermarkCanvasLayerController _watermarkLayerController;
  late final WatermarkCanvasPainter _watermarkCanvasPainter;
  late final FrameAlignedPointerMoveDispatcher _pointerMoveDispatcher;
  late final FrameAlignedEventDispatcher<_HoverFrameEvent> _hoverMoveDispatcher;
  late final FrameAlignedEventDispatcher<_EraserMoveEvent>
  _eraserMoveDispatcher;
  DrawState? _lastObservedState;
  DrawState? _cachedState;
  DrawStateView? _cachedStateView;
  SelectionConfig? _cachedInputSelectionConfigSource;
  SelectionConfig? _cachedInputSelectionConfig;
  double? _cachedInputSelectionScale;
  var _isRefreshingAutoResizeTextLayoutsAfterFontLoad = false;

  CoordinateService get _coords {
    _updateCoordinateServiceIfNeeded();
    return _coordinateService!;
  }

  double _effectiveScaleFactor() {
    final requested = widget.scaleFactor;
    if (!_doubleEquals(requested, 1)) {
      return requested;
    }
    final zoom = widget.store.state.application.view.camera.zoom;
    return _doubleEquals(zoom, 0) ? 1 : zoom;
  }

  void _updateCoordinateServiceIfNeeded() {
    final currentService = _coordinateService;
    final currentCamera = widget.store.state.application.view.camera;
    final effectiveScale = _effectiveScaleFactor();

    if (currentService == null ||
        currentService.camera != currentCamera ||
        !_doubleEquals(currentService.scaleFactor, effectiveScale)) {
      _coordinateService = CoordinateService(
        camera: currentCamera,
        scaleFactor: effectiveScale,
      );
    }
  }

  KeyModifiers get _currentModifiers => KeyModifiers(
    shift: _isShiftPressed,
    control: _isControlPressed,
    alt: _isAltPressed,
  );

  DrawPoint _transformPosition(Offset localPosition) =>
      _coords.fromOffset(localPosition);

  Future<void> _recreatePluginCoordinator() async {
    // Create dependencies.
    final dependencies = ControllerDependencies(
      dispatcher: widget.store.call,
      stateProvider: widget.store,
      contextProvider: () => widget.store.context,
      selectionConfigProvider: () =>
          _resolveSelectionConfigForInput(widget.store.state),
    );
    final inputLog = widget.store.context.log.input;

    // Create plugin context.
    final pluginContext = pluginFactory.createPluginContext(dependencies);

    // Build middleware list.
    final middlewares = <InputMiddleware>[
      // Validation middleware (always first).
      const ValidationMiddleware(),

      // Optional: debug logging.
      if (widget.enableDebugLogging) const LoggingMiddleware(verbose: true),

      // Optional: performance monitoring.
      if (widget.enablePerformanceMonitoring)
        PerformanceMiddleware(
          onMeasure: (eventType, duration) {
            if (duration.inMilliseconds > 16) {
              inputLog.warning('Slow input event', {
                'type': eventType,
                'duration_ms': duration.inMilliseconds,
              });
            }
          },
        ),

      // User-defined middleware.
      ...?widget.middlewares,
    ];

    // Create coordinator.
    _pluginCoordinator = PluginInputCoordinator(
      pluginContext: pluginContext,
      middlewares: middlewares,
    );

    // Register standard plugins.
    final standardPlugins = pluginFactory.createStandardPlugins(
      currentToolTypeId: widget.currentToolTypeId,
      isSelectionToolActive: widget.isSelectionToolActive,
    );

    for (final plugin in standardPlugins) {
      await _pluginCoordinator.registry.register(plugin);
    }

    // Register custom plugins.
    if (widget.customPlugins != null) {
      for (final plugin in widget.customPlugins!) {
        await _pluginCoordinator.registry.register(plugin);
      }
    }

    // Print stats (debug mode).
    if (widget.enableDebugLogging) {
      final stats = _pluginCoordinator.getStats();
      inputLog.debug('Plugin input initialized', {
        'middlewares': stats['middlewares'],
        'plugins': stats['totalPlugins'],
        'pluginsByPriority': stats['pluginsByPriority'],
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final initialState = widget.store.state;
    _textFocusNode = FocusNode(onKeyEvent: _handleTextFocusKeyEvent);
    _pointerMoveDispatcher = FrameAlignedPointerMoveDispatcher(
      dispatchMove: _dispatchPointerMoveEvent,
      shouldCoalesce: _shouldFrameCoalescePointerMove,
      mergeCoalescedEvents: _mergeCoalescedPointerMoveEvents,
    );
    _hoverMoveDispatcher = FrameAlignedEventDispatcher<_HoverFrameEvent>(
      dispatchEvent: _dispatchHoverFrameEvent,
      shouldCoalesce: () => _activePointerIds.isEmpty,
      mergePendingEvents: (pending, incoming) => pending.mergeWith(incoming),
    );
    _eraserMoveDispatcher = FrameAlignedEventDispatcher<_EraserMoveEvent>(
      dispatchEvent: _dispatchEraserMove,
      shouldCoalesce: () => _eraserPointerIds.length <= 1,
    );
    unawaited(_recreatePluginCoordinator());
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: widget.store.context.editOperations,
    );
    _lastObservedState = initialState;
    _watermarkLayerController = WatermarkCanvasLayerController(
      initialState: WatermarkCanvasLayerState(
        camera: initialState.application.view.camera,
        scaleFactor: _effectiveScaleFactor(),
        config: initialState.domain.document.globalElements.watermark,
      ),
    );
    _watermarkCanvasPainter = WatermarkCanvasPainter(
      controller: _watermarkLayerController,
    );

    // Preload GPU shaders for optimal first-frame performance.
    unawaited(GridShaderManager.instance.load());
    unawaited(RectangleShaderManager.instance.load());
    unawaited(FilterShaderManager.instance.load());
    unawaited(HighlightMaskShaderManager.instance.load());

    _stateUnsubscribe = widget.store.listen(
      _handleStateChange,
      changeTypes: _stateChangeTypes,
    );

    _configSubscription = widget.store.configStream.listen(_handleConfigChange);
    textRenderingCacheRevisionListenable.addListener(
      _handleTextRenderingCacheInvalidation,
    );
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChange);
    _updateCursorIfChanged(
      _resolveCursorForState(widget.store.state, _lastPointerPosition),
    );
  }

  @override
  void didUpdateWidget(PluginDrawCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRecreateCoordinator =
        oldWidget.store != widget.store ||
        oldWidget.middlewares != widget.middlewares ||
        oldWidget.customPlugins != widget.customPlugins;
    final toolChanged =
        oldWidget.currentToolTypeId != widget.currentToolTypeId ||
        oldWidget.isSelectionToolActive != widget.isSelectionToolActive;
    final eraserModeChanged =
        oldWidget.isEraserToolActive != widget.isEraserToolActive;

    if (shouldRecreateCoordinator) {
      _pointerMoveDispatcher.reset();
      _hoverMoveDispatcher.reset();
      // Dispose old coordinator
      unawaited(_pluginCoordinator.dispose());

      if (oldWidget.store != widget.store) {
        _stateUnsubscribe?.call();
        _stateUnsubscribe = null;
        unawaited(_configSubscription?.cancel());
        _lastObservedState = widget.store.state;
        _cachedState = null;
        _cachedStateView = null;
        _cachedInputSelectionConfigSource = null;
        _cachedInputSelectionConfig = null;
        _cachedInputSelectionScale = null;

        _stateUnsubscribe = widget.store.listen(
          _handleStateChange,
          changeTypes: _stateChangeTypes,
        );

        _configSubscription = widget.store.configStream.listen(
          _handleConfigChange,
        );

        _stateViewBuilder = DrawStateViewBuilder(
          editOperations: widget.store.context.editOperations,
        );
      }
      _eraserHitTesterByType.clear();

      // Recreate coordinator
      unawaited(_recreatePluginCoordinator());
    }
    if (toolChanged) {
      unawaited(_resetInteractionForToolChange());
      if (!shouldRecreateCoordinator) {
        _updateToolPlugins(
          toolTypeId: widget.currentToolTypeId,
          isSelectionToolActive: widget.isSelectionToolActive,
        );
      }
    }
    if (eraserModeChanged && !widget.isEraserToolActive) {
      _clearEraserStrokeState();
    }

    _updateCursorIfChanged(
      _resolveCursorForState(widget.store.state, _lastPointerPosition),
    );
    _syncWatermarkLayerState(widget.store.state);
  }

  @override
  void dispose() {
    _stateUnsubscribe?.call();
    _stateUnsubscribe = null;
    unawaited(_configSubscription?.cancel());
    textRenderingCacheRevisionListenable.removeListener(
      _handleTextRenderingCacheInvalidation,
    );
    PaintingBinding.instance.systemFonts.removeListener(
      _handleSystemFontsChange,
    );
    _focusNode.dispose();
    _textController?.dispose();
    _textFocusNode.dispose();
    _cursorNotifier.dispose();
    _eraserCursorPositionNotifier.dispose();
    _watermarkLayerController.dispose();
    unawaited(_pointerMoveDispatcher.dispose());
    unawaited(_hoverMoveDispatcher.dispose());
    unawaited(_eraserMoveDispatcher.dispose());
    unawaited(_pluginCoordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateView = _buildStateView(widget.store.state);
    final config = widget.store.config;
    final selectionConfig = _resolveSelectionConfig(widget.store.state);
    final scaleFactor = _effectiveScaleFactor();
    _syncWatermarkLayerState(stateView.state, scaleFactor: scaleFactor);
    final elementRegistry = widget.store.context.elementRegistry;
    final locale = Localizations.maybeLocaleOf(context);
    final camera = stateView.state.application.view.camera;
    final textOverlay = _buildTextEditorOverlay(
      state: widget.store.state,
      scaleFactor: scaleFactor,
      locale: locale,
    );
    final promoteEraserPreviewToDynamicLayer =
        widget.isEraserToolActive &&
        _pendingErasePreviewElementsById.isNotEmpty;
    final optimizationPlan = promoteEraserPreviewToDynamicLayer
        ? null
        : resolveDynamicSceneOptimizationPlan(
            view: stateView,
            activeToolTypeId: widget.currentToolTypeId,
          );
    final optimizedDynamicElementIds = promoteEraserPreviewToDynamicLayer
        ? const <String>{}
        : optimizationPlan?.optimizedElementIds ?? const <String>{};
    final baseDynamicLayerStartIndex = optimizedDynamicElementIds.isEmpty
        ? _resolveDynamicLayerStartIndex(stateView)
        : null;
    final dynamicLayerStartIndex = promoteEraserPreviewToDynamicLayer
        ? 0
        : baseDynamicLayerStartIndex;

    final baseStaticPreviewElements = optimizedDynamicElementIds.isEmpty
        ? _previewElementsForStatic(stateView, baseDynamicLayerStartIndex)
        : _previewElementsForStaticOptimizedScene(
            stateView,
            optimizationPlan!.staticHiddenElementIds,
          );
    final baseDynamicPreviewElements = optimizedDynamicElementIds.isEmpty
        ? _previewElementsForDynamic(stateView, baseDynamicLayerStartIndex)
        : _previewElementsForDynamicOptimizedScene(
            stateView,
            optimizationPlan!.optimizedElementIds,
          );

    late final Map<String, ElementState> staticPreviewElements;
    late final Map<String, ElementState> dynamicPreviewElements;
    if (promoteEraserPreviewToDynamicLayer) {
      final eraserPreviewElements = _snapshotPendingEraserPreviewElements();
      final wholeScenePreviewElements = _mergePreviewElements(
        basePreviewElements: baseStaticPreviewElements,
        overridePreviewElements: baseDynamicPreviewElements,
      );
      staticPreviewElements = const <String, ElementState>{};
      dynamicPreviewElements = _mergePreviewElements(
        basePreviewElements: wholeScenePreviewElements,
        overridePreviewElements: eraserPreviewElements,
      );
    } else {
      staticPreviewElements = baseStaticPreviewElements;
      dynamicPreviewElements = baseDynamicPreviewElements;
    }
    final eraserCursorOverlay = _buildEraserCursorOverlay();
    final creatingSnapshot = _extractCreatingSnapshot(stateView);
    final hasHighlights = stateView.highlightMaskScene.hasHighlights;
    final globalElements = stateView.globalElements;
    final highlightMask = globalElements.highlightMask;
    final ownsWholeScene = dynamicLayerStartIndex == 0;
    final hasDynamicContent =
        dynamicLayerStartIndex != null ||
        creatingSnapshot != null ||
        dynamicPreviewElements.isNotEmpty;
    final highlightMaskLayer = resolveHighlightMaskLayer(
      hasHighlights: hasHighlights,
      hasDynamicContent: hasDynamicContent,
      config: highlightMask,
    );
    final textRenderingCacheRevision =
        textRenderingCacheRevisionListenable.value;

    // Build precise render keys for each canvas layer.
    final staticRenderKey = StaticCanvasRenderKey(
      documentVersion: stateView.state.domain.document.elementsVersion,
      textRenderingCacheRevision: textRenderingCacheRevision,
      camera: camera,
      previewElementsById: staticPreviewElements,
      dynamicLayerStartIndex: dynamicLayerStartIndex,
      skipBaseElementScene: ownsWholeScene,
      scaleFactor: scaleFactor,
      canvasConfig: config.canvas,
      gridConfig: config.grid,
      highlightMaskLayer: highlightMaskLayer,
      highlightMaskConfig: highlightMask,
      elementRegistry: elementRegistry,
      performanceMonitoringEnabled: widget.enablePerformanceMonitoring,
      locale: locale,
    );

    final dynamicRenderKey = DynamicCanvasRenderKey(
      creatingElement: creatingSnapshot,
      effectiveSelection: stateView.effectiveSelection,
      boxSelectionBounds: _extractBoxSelectionBounds(stateView),
      selectedIds: stateView.selectedIds,
      hoveredElementId: _hoveredSelectionElementId,
      hoveredBindingElementId: _hoveredBindingElementId,
      hoveredArrowHandle: _hoveredArrowHandle,
      activeArrowHandle: _resolveActiveArrowHandle(stateView),
      arrowDeleteIndicatorVisible: _isArrowDeleteIndicatorVisible(stateView),
      hoverSelectionConfig: _resolveHoverSelectionConfig(),
      snapGuides: stateView.snapGuides,
      documentVersion: stateView.state.domain.document.elementsVersion,
      textRenderingCacheRevision: textRenderingCacheRevision,
      camera: camera,
      previewElementsById: dynamicPreviewElements,
      optimizedDynamicElementIds: optimizedDynamicElementIds,
      dynamicLayerStartIndex: dynamicLayerStartIndex,
      rendersWholeElementScene: ownsWholeScene,
      scaleFactor: scaleFactor,
      selectionConfig: selectionConfig,
      boxSelectionConfig: config.boxSelection,
      snapConfig: config.snap,
      highlightMaskLayer: highlightMaskLayer,
      highlightMaskConfig: highlightMask,
      elementRegistry: elementRegistry,
      performanceMonitoringEnabled: widget.enablePerformanceMonitoring,
      locale: locale,
    );

    final paintStack = Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      onPointerSignal: _handlePointerSignal,
      child: Stack(
        children: [
          RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: StaticCanvasPainter(
                renderKey: staticRenderKey,
                stateView: stateView,
              ),
              size: widget.size,
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: DynamicCanvasPainter(
                renderKey: dynamicRenderKey,
                stateView: stateView,
              ),
              size: widget.size,
            ),
          ),
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                isComplex: true,
                painter: _watermarkCanvasPainter,
                size: widget.size,
              ),
            ),
          ),
          ?textOverlay,
          ?eraserCursorOverlay,
        ],
      ),
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<MouseCursor>(
        valueListenable: _cursorNotifier,
        child: paintStack,
        builder: (context, cursor, child) => MouseRegion(
          cursor: cursor,
          onEnter: _handlePointerEnter,
          onHover: _handlePointerHover,
          onExit: _handlePointerExit,
          child: child,
        ),
      ),
    );
  }

  /// Extract preview elements for static canvas (excludes creating elements).
  Map<String, ElementState> _previewElementsForStatic(
    DrawStateView view,
    int? dynamicLayerStartIndex,
  ) {
    final interaction = view.state.application.interaction;
    if (interaction is CreatingState) {
      return const <String, ElementState>{};
    }
    if (interaction is TextEditingState && interaction.isNew) {
      // Avoid double-rendering the draft text (static + dynamic) while
      // creating.
      return const <String, ElementState>{};
    }
    if (dynamicLayerStartIndex == null) {
      return view.previewElementsById;
    }

    final previewElements = view.previewElementsById;
    if (previewElements.isEmpty) {
      return previewElements;
    }

    final document = view.state.domain.document;
    final filtered = <String, ElementState>{};
    for (final entry in previewElements.entries) {
      final orderIndex = document.getOrderIndex(entry.key);
      if (orderIndex == null || orderIndex < dynamicLayerStartIndex) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  /// Extract preview elements for dynamic canvas (excludes creating elements).
  Map<String, ElementState> _previewElementsForDynamic(
    DrawStateView view,
    int? dynamicLayerStartIndex,
  ) {
    final interaction = view.state.application.interaction;
    if (interaction is CreatingState) {
      return const <String, ElementState>{};
    }

    // When creating a new text element, add it to the dynamic layer preview
    // so its background is rendered on top of existing elements.
    if (interaction is TextEditingState && interaction.isNew) {
      final textElement = ElementState(
        id: interaction.elementId,
        rect: interaction.rect,
        rotation: interaction.rotation,
        opacity: interaction.opacity,
        zIndex: view.state.domain.document.elements.length,
        data: interaction.draftData,
      );
      return {interaction.elementId: textElement};
    }

    if (dynamicLayerStartIndex == null) {
      return const <String, ElementState>{};
    }

    final previewElements = view.previewElementsById;
    if (previewElements.isEmpty) {
      return previewElements;
    }

    final document = view.state.domain.document;
    final filtered = <String, ElementState>{};
    for (final entry in previewElements.entries) {
      final orderIndex = document.getOrderIndex(entry.key);
      if (orderIndex != null && orderIndex >= dynamicLayerStartIndex) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  Map<String, ElementState> _previewElementsForStaticOptimizedScene(
    DrawStateView view,
    Set<String> hiddenElementIds,
  ) {
    if (hiddenElementIds.isEmpty) {
      return const <String, ElementState>{};
    }
    final previews = <String, ElementState>{};
    final document = view.state.domain.document;
    for (final elementId in hiddenElementIds) {
      final element = document.getElementById(elementId);
      if (element == null) {
        continue;
      }
      if (element.opacity == 0) {
        previews[elementId] = element;
      } else {
        previews[elementId] = element.copyWith(opacity: 0);
      }
    }
    return previews;
  }

  Map<String, ElementState> _previewElementsForDynamicOptimizedScene(
    DrawStateView view,
    Set<String> optimizedElementIds,
  ) {
    if (optimizedElementIds.isEmpty) {
      return const <String, ElementState>{};
    }

    final previews = <String, ElementState>{};
    final document = view.state.domain.document;
    for (final elementId in optimizedElementIds) {
      final preview = view.previewElementsById[elementId];
      if (preview != null) {
        previews[elementId] = preview;
        continue;
      }
      final persisted = document.getElementById(elementId);
      if (persisted != null) {
        previews[elementId] = persisted;
      }
    }
    return previews;
  }

  Map<String, ElementState> _snapshotPendingEraserPreviewElements() {
    if (_pendingErasePreviewElementsById.isEmpty) {
      return const <String, ElementState>{};
    }
    return Map<String, ElementState>.from(_pendingErasePreviewElementsById);
  }

  Map<String, ElementState> _mergePreviewElements({
    required Map<String, ElementState> basePreviewElements,
    required Map<String, ElementState> overridePreviewElements,
  }) {
    if (overridePreviewElements.isEmpty) {
      return basePreviewElements;
    }
    if (basePreviewElements.isEmpty) {
      return Map<String, ElementState>.from(overridePreviewElements);
    }
    return Map<String, ElementState>.from(basePreviewElements)
      ..addAll(overridePreviewElements);
  }

  Widget? _buildEraserCursorOverlay() {
    if (!widget.isEraserToolActive) {
      return null;
    }
    const diameter = _eraserCursorRadius * 2;
    return ValueListenableBuilder<DrawPoint?>(
      valueListenable: _eraserCursorPositionNotifier,
      builder: (context, pointer, child) {
        if (pointer == null || !_isPointerInside) {
          return const SizedBox.shrink();
        }
        final screenPosition = _coords.worldToScreen(pointer);
        return Positioned(
          left: screenPosition.x - _eraserCursorRadius,
          top: screenPosition.y - _eraserCursorRadius,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: Container(
          key: _eraserCursorOverlayKey,
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.55),
              width: _eraserCursorBorderWidth,
            ),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }

  int? _resolveDynamicLayerStartIndex(DrawStateView view) =>
      resolveDynamicLayerStartIndex(view);

  /// Extract creating element snapshot from state view.
  CreatingElementSnapshot? _extractCreatingSnapshot(DrawStateView view) {
    final interaction = view.state.application.interaction;
    if (interaction is CreatingState) {
      return CreatingElementSnapshot(
        element: interaction.element,
        currentRect: interaction.currentRect,
        creationRevision: _resolveCreationRevision(interaction.creationMode),
      );
    }
    return null;
  }

  int _resolveCreationRevision(CreationMode mode) {
    if (mode is FreeDrawCreationMode) {
      return mode.revision;
    }
    return 0;
  }

  /// Extract box selection bounds from state view.
  DrawRect? _extractBoxSelectionBounds(DrawStateView view) {
    final interaction = view.state.application.interaction;
    if (interaction is BoxSelectingState) {
      return interaction.bounds;
    }
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _updateKeyboardModifiers(event, true);
    } else if (event is KeyUpEvent) {
      _updateKeyboardModifiers(event, false);
    }
    return KeyEventResult.ignored;
  }

  void _updateKeyboardModifiers(KeyEvent event, bool isPressed) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.shift:
      case LogicalKeyboardKey.shiftLeft:
      case LogicalKeyboardKey.shiftRight:
        _setShiftPressed(isPressed);
        return;
      case LogicalKeyboardKey.control:
      case LogicalKeyboardKey.controlLeft:
      case LogicalKeyboardKey.controlRight:
        _setControlPressed(isPressed);
        return;
      case LogicalKeyboardKey.alt:
      case LogicalKeyboardKey.altLeft:
      case LogicalKeyboardKey.altRight:
        _setAltPressed(isPressed);
        return;
      default:
        break;
    }
  }

  void _setShiftPressed(bool isPressed) {
    if (_isShiftPressed == isPressed) {
      return;
    }
    _isShiftPressed = isPressed;
    _flushPendingPointerMoveForModifierChange();
  }

  void _setControlPressed(bool isPressed) {
    if (_isControlPressed == isPressed) {
      return;
    }
    _isControlPressed = isPressed;
    _flushPendingPointerMoveForModifierChange();
  }

  void _setAltPressed(bool isPressed) {
    if (_isAltPressed == isPressed) {
      return;
    }
    _isAltPressed = isPressed;
    _flushPendingPointerMoveForModifierChange();
  }

  void _flushPendingPointerMoveForModifierChange() {
    if (_activePointerIds.isEmpty) {
      return;
    }
    unawaited(_pointerMoveDispatcher.flush());
  }

  void _syncKeyboardModifiers() {
    final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
    _isShiftPressed =
        keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        keysPressed.contains(LogicalKeyboardKey.shiftRight) ||
        keysPressed.contains(LogicalKeyboardKey.shift);
    _isControlPressed =
        keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        keysPressed.contains(LogicalKeyboardKey.controlRight) ||
        keysPressed.contains(LogicalKeyboardKey.control);
    _isAltPressed =
        keysPressed.contains(LogicalKeyboardKey.altLeft) ||
        keysPressed.contains(LogicalKeyboardKey.altRight) ||
        keysPressed.contains(LogicalKeyboardKey.alt);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    if (_isMousePointer(event)) {
      if (_isMiddleMouseButton(event.buttons)) {
        _hoverMoveDispatcher.reset();
        _startMiddlePan(event);
        return;
      }
      if (!_isPrimaryMouseButton(event.buttons)) {
        return;
      }
    }
    _activePointerIds.add(event.pointer);
    _pointerMoveDispatcher.reset();
    _hoverMoveDispatcher.reset();
    if (widget.isEraserToolActive) {
      final isFirstEraserPointer = _eraserPointerIds.isEmpty;
      _eraserPointerIds.add(event.pointer);
      if (isFirstEraserPointer) {
        _eraserMoveDispatcher.reset();
        _lastEraserProcessedPositions.clear();
      }
      _lastEraserProcessedPositions.remove(event.pointer);
      final previewChanged = _markElementsForErase(
        pointerId: event.pointer,
        position: position,
      );
      if (previewChanged && mounted) {
        setState(() {});
      }
      return;
    }
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerDownInputEvent(
          position: position.copyWith(pressure: event.pressure),
          modifiers: _currentModifiers,
          pressure: event.pressure,
        ),
      ),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    final hasActivePointer = _activePointerIds.contains(event.pointer);
    if (!hasActivePointer) {
      _queueHoverUpdate(position: position);
    }
    if (_handleMiddlePanMove(event)) {
      return;
    }
    if (!hasActivePointer) {
      return;
    }
    if (widget.isEraserToolActive) {
      if (_eraserPointerIds.contains(event.pointer)) {
        _eraserMoveDispatcher.dispatch(
          _EraserMoveEvent(pointerId: event.pointer, position: position),
        );
      }
      return;
    }
    _pointerMoveDispatcher.dispatch(
      PointerMoveInputEvent(
        position: position.copyWith(pressure: event.pressure),
        modifiers: _currentModifiers,
        pressure: event.pressure,
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    if (_middlePanPointerId == event.pointer) {
      _stopMiddlePan();
      _activePointerIds.remove(event.pointer);
      return;
    }
    if (!_activePointerIds.remove(event.pointer)) {
      return;
    }
    if (widget.isEraserToolActive) {
      _eraserPointerIds.remove(event.pointer);
      if (_eraserPointerIds.isEmpty) {
        unawaited(_finishEraserStroke());
      }
      return;
    }
    final modifiers = _currentModifiers;
    unawaited(
      _dispatchPointerUpInput(position: position, modifiers: modifiers),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _syncKeyboardModifiers();
    final position = _transformPosition(event.localPosition);
    final modifiers = _currentModifiers;
    if (_middlePanPointerId == event.pointer) {
      _stopMiddlePan();
      _activePointerIds.remove(event.pointer);
      return;
    }
    if (!_activePointerIds.remove(event.pointer)) {
      return;
    }
    if (widget.isEraserToolActive) {
      _eraserPointerIds.remove(event.pointer);
      if (_eraserPointerIds.isEmpty) {
        unawaited(_finishEraserStroke());
      }
      return;
    }
    unawaited(
      _dispatchPointerCancelInput(position: position, modifiers: modifiers),
    );
  }

  Future<void> _dispatchPointerMoveEvent(PointerMoveInputEvent event) async {
    await _pluginCoordinator.handleEvent(event);
  }

  Future<void> _dispatchHoverFrameEvent(_HoverFrameEvent event) async {
    if (_activePointerIds.isNotEmpty ||
        _middlePanPointerId != null ||
        !_isPointerInside) {
      return;
    }
    _updateCursorAndHoverForPosition(event.position);
    if (!event.dispatchPluginHover || widget.isEraserToolActive) {
      return;
    }
    await _pluginCoordinator.handleEvent(
      PointerHoverInputEvent(
        position: event.position,
        modifiers: event.modifiers,
      ),
    );
  }

  Future<void> _dispatchEraserMove(_EraserMoveEvent event) async {
    if (!widget.isEraserToolActive) {
      return;
    }
    final previewChanged = _markElementsForErase(
      pointerId: event.pointerId,
      position: event.position,
    );
    if (previewChanged && mounted) {
      setState(() {});
    }
  }

  Future<void> _finishEraserStroke() async {
    await _eraserMoveDispatcher.flush();
    _lastEraserProcessedPositions.clear();
    await _commitPendingErase();
  }

  bool _shouldFrameCoalescePointerMove() {
    final interaction = widget.store.state.application.interaction;
    if (interaction is CreatingState &&
        interaction.creationMode is FreeDrawCreationMode) {
      final mode = interaction.creationMode as FreeDrawCreationMode;
      if (mode.isLineActive) {
        return true;
      }
    }

    if (_shouldBatchFreeDrawMoves()) {
      return true;
    }

    if (interaction is CreatingState) {
      return interaction.creationMode is! FreeDrawCreationMode;
    }

    return interaction is EditingState ||
        interaction is BoxSelectingState ||
        interaction is DragPendingState;
  }

  bool _shouldBatchFreeDrawMoves() {
    if (_isShiftPressed) {
      return false;
    }
    if (widget.currentToolTypeId == FreeDrawData.typeIdToken) {
      return true;
    }
    final interaction = widget.store.state.application.interaction;
    return interaction is CreatingState &&
        interaction.elementData is FreeDrawData;
  }

  PointerMoveInputEvent _mergeCoalescedPointerMoveEvents(
    PointerMoveInputEvent pending,
    PointerMoveInputEvent incoming,
  ) {
    final canBatchSamples =
        _shouldBatchFreeDrawMoves() &&
        !pending.modifiers.shift &&
        !incoming.modifiers.shift &&
        pending.modifiers.control == incoming.modifiers.control &&
        pending.modifiers.alt == incoming.modifiers.alt;
    if (canBatchSamples) {
      return pending.mergeWith(incoming);
    }
    return incoming;
  }

  Future<void> _dispatchPointerUpInput({
    required DrawPoint position,
    required KeyModifiers modifiers,
  }) async {
    await _pointerMoveDispatcher.flush();
    await _pluginCoordinator.handleEvent(
      PointerUpInputEvent(position: position, modifiers: modifiers),
    );
  }

  Future<void> _dispatchPointerCancelInput({
    required DrawPoint position,
    required KeyModifiers modifiers,
  }) async {
    await _pointerMoveDispatcher.flush();
    await _pluginCoordinator.handleEvent(
      PointerCancelInputEvent(position: position, modifiers: modifiers),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    _syncKeyboardModifiers();
    if (event is PointerScaleEvent) {
      _zoomCamera(event.scale, event.localPosition);
      return;
    }

    if (event is! PointerScrollEvent) {
      return;
    }

    if (_isControlPressed && _isShiftPressed) {
      final delta = _resolveVerticalScrollDelta(event);
      unawaited(widget.store.dispatch(MoveCamera(dx: 0, dy: -delta)));
      return;
    }

    if (_isControlPressed) {
      final delta = _resolvePrimaryScrollDelta(event);
      if (delta == null) {
        return;
      }
      final scale = delta > 0 ? 0.9 : 1.1;
      _zoomCamera(scale, event.localPosition);
      return;
    }

    if (_isShiftPressed) {
      final delta = _resolveHorizontalScrollDelta(event);
      unawaited(widget.store.dispatch(MoveCamera(dx: -delta, dy: 0)));
      return;
    }

    final toolTypeId = widget.currentToolTypeId;
    if (toolTypeId == TextData.typeIdToken ||
        toolTypeId == SerialNumberData.typeIdToken) {
      _adjustFontSize(event);
      return;
    }
    if (toolTypeId == RectangleData.typeIdToken ||
        toolTypeId == ArrowData.typeIdToken ||
        toolTypeId == LineData.typeIdToken ||
        toolTypeId == FreeDrawData.typeIdToken ||
        (toolTypeId == null && widget.isSelectionToolActive)) {
      _adjustStrokeWidth(event);
      return;
    }

    unawaited(
      widget.store.dispatch(
        MoveCamera(dx: -event.scrollDelta.dx, dy: -event.scrollDelta.dy),
      ),
    );
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    _isPointerInside = true;
    final position = _recordPointerPosition(event.localPosition);
    _hoverMoveDispatcher.reset();
    _updateCursorAndHoverForPosition(position);
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    _queueHoverUpdate(
      position: position,
      dispatchPluginHover: !widget.isEraserToolActive,
    );
  }

  void _handlePointerExit(PointerExitEvent event) {
    _isPointerInside = false;
    _lastPointerPosition = null;
    _eraserCursorPositionNotifier.value = null;
    _hoverMoveDispatcher.reset();
    if (_hoveredSelectionElementId != null ||
        _hoveredBindingElementId != null ||
        _hoveredArrowHandle != null) {
      setState(() {
        _hoveredSelectionElementId = null;
        _hoveredBindingElementId = null;
        _hoveredArrowHandle = null;
      });
    }
    final nextCursor = _resolveCursorForState(widget.store.state, null);
    _updateCursorIfChanged(nextCursor);
  }

  void _queueHoverUpdate({
    required DrawPoint position,
    bool dispatchPluginHover = false,
  }) {
    if (_middlePanPointerId != null || _activePointerIds.isNotEmpty) {
      return;
    }
    _hoverMoveDispatcher.dispatch(
      _HoverFrameEvent(
        position: position,
        modifiers: _currentModifiers,
        dispatchPluginHover: dispatchPluginHover,
      ),
    );
  }

  DrawPoint _recordPointerPosition(Offset localPosition) {
    _syncKeyboardModifiers();
    final position = _transformPosition(localPosition);
    _lastPointerPosition = position;
    _eraserCursorPositionNotifier.value = position;
    _isPointerInside = true;
    return position;
  }

  bool _markElementsForErase({
    required int pointerId,
    required DrawPoint position,
  }) {
    final stateView = _buildStateView(widget.store.state);
    final tolerance = _eraserCursorRadius / _effectiveScaleFactor();

    final previous = _lastEraserProcessedPositions[pointerId];
    _lastEraserProcessedPositions[pointerId] = position;
    final strokeStart = previous ?? position;
    final samplePoints = _buildEraserStrokeSamples(
      start: strokeStart,
      end: position,
      tolerance: tolerance,
      includeStart: previous == null,
    );
    if (samplePoints.isEmpty) {
      return false;
    }
    final queryRect = _buildEraserStrokeQueryRect(
      start: strokeStart,
      end: position,
      tolerance: tolerance,
    );
    return _markElementsForEraseAcrossStroke(
      stateView: stateView,
      samplePoints: samplePoints,
      queryRect: queryRect,
      tolerance: tolerance,
    );
  }

  List<DrawPoint> _buildEraserStrokeSamples({
    required DrawPoint start,
    required DrawPoint end,
    required double tolerance,
    required bool includeStart,
  }) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final distanceSquared = dx * dx + dy * dy;
    if (_doubleEquals(distanceSquared, 0)) {
      return includeStart ? <DrawPoint>[end] : const <DrawPoint>[];
    }

    final sampleStep = tolerance * 0.5;
    if (sampleStep <= 0) {
      return includeStart ? <DrawPoint>[start, end] : <DrawPoint>[end];
    }

    final distance = math.sqrt(distanceSquared);
    final sampleCount = math.max(1, (distance / sampleStep).ceil());
    final samples = <DrawPoint>[if (includeStart) start];
    for (var i = 1; i <= sampleCount; i++) {
      final t = i / sampleCount;
      samples.add(DrawPoint(x: start.x + dx * t, y: start.y + dy * t));
    }
    return samples;
  }

  DrawRect _buildEraserStrokeQueryRect({
    required DrawPoint start,
    required DrawPoint end,
    required double tolerance,
  }) => DrawRect(
    minX: math.min(start.x, end.x) - tolerance,
    minY: math.min(start.y, end.y) - tolerance,
    maxX: math.max(start.x, end.x) + tolerance,
    maxY: math.max(start.y, end.y) + tolerance,
  );

  bool _markElementsForEraseAcrossStroke({
    required DrawStateView stateView,
    required List<DrawPoint> samplePoints,
    required DrawRect queryRect,
    required double tolerance,
  }) {
    final document = stateView.state.domain.document;
    var hasNewHits = false;
    document.visitElementsInRect(queryRect, (candidate) {
      if (_pendingErasePreviewElementsById.containsKey(candidate.id)) {
        return true;
      }
      final element = stateView.effectiveElement(candidate);
      if (_isElementHitByAnyEraserSample(
        element: element,
        samplePoints: samplePoints,
        tolerance: tolerance,
      )) {
        if (_queueElementForErasePreview(element)) {
          hasNewHits = true;
        }
      }
      return true;
    });
    return hasNewHits;
  }

  bool _isElementHitByAnyEraserSample({
    required ElementState element,
    required List<DrawPoint> samplePoints,
    required double tolerance,
  }) {
    final hitTester = _resolveEraserHitTester(element);
    for (final sample in samplePoints) {
      final isHit =
          hitTester?.hitTest(
            element: element,
            position: sample,
            tolerance: tolerance,
          ) ??
          _isInsideRectWithTolerance(
            rect: element.rect,
            rotation: element.rotation,
            position: sample,
            tolerance: tolerance,
          );
      if (isHit) {
        return true;
      }
    }
    return false;
  }

  ElementHitTester? _resolveEraserHitTester(ElementState element) {
    final typeId = element.typeId;
    if (_eraserHitTesterByType.containsKey(typeId)) {
      return _eraserHitTesterByType[typeId];
    }
    final hitTester = widget.store.context.elementRegistry
        .getDefinition(typeId)
        ?.hitTester;
    _eraserHitTesterByType[typeId] = hitTester;
    return hitTester;
  }

  bool _queueElementForErasePreview(ElementState element) {
    if (_pendingErasePreviewElementsById.containsKey(element.id)) {
      return false;
    }
    final previewOpacity = (element.opacity * _eraserPreviewOpacityFactor)
        .clamp(0.0, 1.0);
    _pendingErasePreviewElementsById[element.id] = element.copyWith(
      opacity: previewOpacity,
    );
    return true;
  }

  bool _isInsideRectWithTolerance({
    required DrawRect rect,
    required double rotation,
    required DrawPoint position,
    required double tolerance,
  }) {
    final local = rotation == 0
        ? position
        : ElementSpace(
            rotation: rotation,
            origin: rect.center,
          ).fromWorld(position);
    return local.x >= rect.minX - tolerance &&
        local.x <= rect.maxX + tolerance &&
        local.y >= rect.minY - tolerance &&
        local.y <= rect.maxY + tolerance;
  }

  Future<void> _commitPendingErase() async {
    if (_pendingErasePreviewElementsById.isEmpty) {
      return;
    }
    final ids = _pendingErasePreviewElementsById.keys.toList(growable: false);
    if (mounted) {
      setState(_pendingErasePreviewElementsById.clear);
    } else {
      _pendingErasePreviewElementsById.clear();
    }
    try {
      await widget.store.dispatch(DeleteElements(elementIds: ids));
    } on Object catch (error, stackTrace) {
      widget.store.context.log.input.error(
        'Failed to delete erased elements',
        error,
        stackTrace,
      );
    }
  }

  void _clearEraserStrokeState() {
    _eraserMoveDispatcher.reset();
    _lastEraserProcessedPositions.clear();
    if (_eraserPointerIds.isNotEmpty) {
      _activePointerIds.removeAll(_eraserPointerIds);
      _eraserPointerIds.clear();
    }
    if (_pendingErasePreviewElementsById.isEmpty) {
      return;
    }
    if (mounted) {
      setState(_pendingErasePreviewElementsById.clear);
      return;
    }
    _pendingErasePreviewElementsById.clear();
  }

  bool _isMousePointer(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse;

  bool _isPrimaryMouseButton(int buttons) =>
      (buttons & kPrimaryMouseButton) != 0;

  bool _isMiddleMouseButton(int buttons) => (buttons & kMiddleMouseButton) != 0;

  void _startMiddlePan(PointerDownEvent event) {
    _middlePanPointerId = event.pointer;
    _lastMiddlePanPosition = event.localPosition;
    _updateCursorIfChanged(_draggingCursor);
  }

  bool _handleMiddlePanMove(PointerMoveEvent event) {
    if (_middlePanPointerId != event.pointer) {
      return false;
    }
    final last = _lastMiddlePanPosition;
    _lastMiddlePanPosition = event.localPosition;
    if (last == null) {
      return true;
    }
    final dx = event.localPosition.dx - last.dx;
    final dy = event.localPosition.dy - last.dy;
    if (_doubleEquals(dx, 0) && _doubleEquals(dy, 0)) {
      return true;
    }
    unawaited(widget.store.dispatch(MoveCamera(dx: dx, dy: dy)));
    return true;
  }

  void _stopMiddlePan() {
    _hoverMoveDispatcher.reset();
    _middlePanPointerId = null;
    _lastMiddlePanPosition = null;
    final position = _lastPointerPosition;
    if (position != null && _isPointerInside) {
      _updateCursorAndHoverForPosition(position);
    } else {
      _updateCursorIfChanged(
        _resolveCursorForState(widget.store.state, position),
      );
      _clearHoverState();
    }
  }

  double? _resolvePrimaryScrollDelta(PointerScrollEvent event) {
    if (!_doubleEquals(event.scrollDelta.dy, 0)) {
      return event.scrollDelta.dy;
    }
    if (!_doubleEquals(event.scrollDelta.dx, 0)) {
      return event.scrollDelta.dx;
    }
    return null;
  }

  double _resolveHorizontalScrollDelta(PointerScrollEvent event) =>
      !_doubleEquals(event.scrollDelta.dx, 0)
      ? event.scrollDelta.dx
      : event.scrollDelta.dy;

  double _resolveVerticalScrollDelta(PointerScrollEvent event) =>
      !_doubleEquals(event.scrollDelta.dy, 0)
      ? event.scrollDelta.dy
      : event.scrollDelta.dx;

  void _zoomCamera(double scale, Offset localPosition) {
    if (!scale.isFinite || scale <= 0 || _doubleEquals(scale, 1)) {
      return;
    }
    unawaited(
      widget.store.dispatch(
        ZoomCamera(
          scale: scale,
          center: DrawPoint(x: localPosition.dx, y: localPosition.dy),
        ),
      ),
    );
  }

  void _adjustStrokeWidth(PointerScrollEvent event) {
    final delta = _resolvePrimaryScrollDelta(event);
    if (delta == null) {
      return;
    }
    final state = widget.store.state;
    final config = widget.store.config;

    // Determine base stroke width from selected elements or config
    final arrowAverage = _resolveAverageSelectedArrowStrokeWidth(state);
    final lineAverage = _resolveAverageSelectedLineStrokeWidth(state);
    final freeDrawAverage = _resolveAverageSelectedFreeDrawStrokeWidth(state);
    final rectangleAverage = _resolveAverageSelectedStrokeWidth(state);
    final base =
        arrowAverage ??
        lineAverage ??
        freeDrawAverage ??
        rectangleAverage ??
        config.arrowStyle.strokeWidth;

    // Find next stepped value
    final next = _findNextSteppedValue(
      base,
      _strokeWidthSteps,
      delta > 0, // scrolling up decreases value
    );

    if (_doubleEquals(next, base)) {
      return;
    }

    // Update selected arrows
    final arrowIds = _resolveArrowSelectionIds(state);
    if (arrowIds.isNotEmpty) {
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: arrowIds, strokeWidth: next),
        ),
      );
    }

    // Update selected rectangles
    final rectangleIds = _resolveRectangleSelectionIds(state);
    if (rectangleIds.isNotEmpty) {
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: rectangleIds, strokeWidth: next),
        ),
      );
    }

    // Update selected lines
    final lineIds = _resolveLineSelectionIds(state);
    if (lineIds.isNotEmpty) {
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: lineIds, strokeWidth: next),
        ),
      );
    }

    // Update selected free draw elements
    final freeDrawIds = _resolveFreeDrawSelectionIds(state);
    if (freeDrawIds.isNotEmpty) {
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: freeDrawIds, strokeWidth: next),
        ),
      );
    }

    // Update arrow style config if needed
    if (!_doubleEquals(next, config.arrowStyle.strokeWidth)) {
      final nextStyle = config.arrowStyle.copyWith(strokeWidth: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(arrowStyle: nextStyle)),
        ),
      );
    }

    // Update rectangle style config if needed
    if (!_doubleEquals(next, config.rectangleStyle.strokeWidth)) {
      final nextStyle = config.rectangleStyle.copyWith(strokeWidth: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(rectangleStyle: nextStyle)),
        ),
      );
    }

    // Update line style config if needed
    if (!_doubleEquals(next, config.lineStyle.strokeWidth)) {
      final nextStyle = config.lineStyle.copyWith(strokeWidth: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(lineStyle: nextStyle)),
        ),
      );
    }

    // Update free draw style config if needed
    if (!_doubleEquals(next, config.freeDrawStyle.strokeWidth)) {
      final nextStyle = config.freeDrawStyle.copyWith(strokeWidth: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(freeDrawStyle: nextStyle)),
        ),
      );
    }
  }

  void _adjustFontSize(PointerScrollEvent event) {
    final delta = _resolvePrimaryScrollDelta(event);
    if (delta == null) {
      return;
    }
    final state = widget.store.state;
    final config = widget.store.config;
    final toolTypeId = widget.currentToolTypeId;
    final base =
        _resolveEditingFontSize(state) ??
        _resolveAverageSelectedFontSize(state) ??
        (toolTypeId == SerialNumberData.typeIdToken
            ? config.serialNumberStyle.fontSize
            : config.textStyle.fontSize);

    // Find next stepped value
    final next = _findNextSteppedValue(
      base,
      _fontSizeSteps,
      delta > 0, // scrolling up decreases value
    );

    if (_doubleEquals(next, base)) {
      return;
    }

    final targetIds = _resolveTextSelectionIds(state);
    if (targetIds.isNotEmpty) {
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: targetIds, fontSize: next),
        ),
      );
    }

    if (!_doubleEquals(next, config.textStyle.fontSize)) {
      final nextStyle = config.textStyle.copyWith(fontSize: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(textStyle: nextStyle)),
        ),
      );
    }

    final serialNumberIds = _resolveSerialNumberSelectionIds(state);
    final updateSerialNumberStyle =
        serialNumberIds.isNotEmpty ||
        toolTypeId == SerialNumberData.typeIdToken;
    if (updateSerialNumberStyle &&
        !_doubleEquals(next, config.serialNumberStyle.fontSize)) {
      final nextStyle = config.serialNumberStyle.copyWith(fontSize: next);
      unawaited(
        widget.store.dispatch(
          UpdateConfig(config.copyWith(serialNumberStyle: nextStyle)),
        ),
      );
    }
  }

  double? _resolveEditingFontSize(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is TextEditingState) {
      return interaction.draftData.fontSize;
    }
    return null;
  }

  /// Finds the next stepped value based on current value and scroll direction.
  ///
  /// [currentValue] - The current value
  /// [steps] - List of stepped values (must be sorted in ascending order)
  /// [decrease] - true to find previous step, false to find next step
  ///
  /// Returns the next stepped value, or the current value if at the edge.
  double _findNextSteppedValue(
    double currentValue,
    List<double> steps,
    bool decrease,
  ) {
    if (steps.isEmpty) {
      return currentValue;
    }

    if (decrease) {
      // Find the largest step that is less than current value
      for (var i = steps.length - 1; i >= 0; i--) {
        if (steps[i] < currentValue - 0.01) {
          return steps[i];
        }
      }
      // Already at or below minimum, return first step
      return steps.first;
    } else {
      // Find the smallest step that is greater than current value
      for (var i = 0; i < steps.length; i++) {
        if (steps[i] > currentValue + 0.01) {
          return steps[i];
        }
      }
      // Already at or above maximum, return last step
      return steps.last;
    }
  }

  double? _resolveAverageSelectedStrokeWidth(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }
    var count = 0;
    var total = 0.0;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      final data = element?.data;
      if (data is RectangleData) {
        total += data.strokeWidth;
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return total / count;
  }

  double? _resolveAverageSelectedArrowStrokeWidth(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }
    var count = 0;
    var total = 0.0;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      final data = element?.data;
      if (data is ArrowData) {
        total += data.strokeWidth;
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return total / count;
  }

  double? _resolveAverageSelectedLineStrokeWidth(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }
    var count = 0;
    var total = 0.0;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      final data = element?.data;
      if (data is LineData) {
        total += data.strokeWidth;
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return total / count;
  }

  double? _resolveAverageSelectedFreeDrawStrokeWidth(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }
    var count = 0;
    var total = 0.0;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      final data = element?.data;
      if (data is FreeDrawData) {
        total += data.strokeWidth;
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return total / count;
  }

  double? _resolveAverageSelectedFontSize(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }
    var count = 0;
    var total = 0.0;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      final data = element?.data;
      if (data is TextData) {
        total += data.fontSize;
        count += 1;
      }
      if (data is SerialNumberData) {
        total += data.fontSize;
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return total / count;
  }

  List<String> _resolveRectangleSelectionIds(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is RectangleData) {
        ids.add(id);
      }
    }
    return ids;
  }

  List<String> _resolveArrowSelectionIds(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is ArrowData) {
        ids.add(id);
      }
    }
    return ids;
  }

  List<String> _resolveLineSelectionIds(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is LineData) {
        ids.add(id);
      }
    }
    return ids;
  }

  List<String> _resolveFreeDrawSelectionIds(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is FreeDrawData) {
        ids.add(id);
      }
    }
    return ids;
  }

  List<String> _resolveTextSelectionIds(DrawState state) {
    final ids = <String>{};
    final selectedIds = state.domain.selection.selectedIds;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData || element?.data is SerialNumberData) {
        ids.add(id);
      }
    }
    final interaction = state.application.interaction;
    if (interaction is TextEditingState) {
      ids.add(interaction.elementId);
    }
    if (ids.isEmpty) {
      return const [];
    }
    return ids.toList(growable: false);
  }

  List<String> _resolveSerialNumberSelectionIds(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }
    final ids = <String>[];
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is SerialNumberData) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// Computes cursor and hover state in a single pass, sharing the
  /// hit test result and arrow-handle lookup between both paths.
  bool _updateCursorAndHoverForPosition(DrawPoint position) {
    final state = widget.store.state;
    final interaction = state.application.interaction;

    // --- cursor early-outs that skip the hit test entirely ---
    if (_middlePanPointerId != null) {
      _updateCursorIfChanged(_draggingCursor);
      return _clearHoverState();
    }
    final lockedCursor = _cursorResolver.resolveLockedCursor(interaction);
    if (lockedCursor != null) {
      _updateCursorIfChanged(lockedCursor);
      return _clearHoverState();
    }
    final interactionCursor = _resolveInteractionCursorWithoutHitTest(
      interaction,
    );
    if (interactionCursor != null) {
      _updateCursorIfChanged(interactionCursor);
      return _clearHoverState();
    }
    if (!_isPointerInside) {
      _updateCursorIfChanged(_idleCursorForCurrentTool);
      return _clearHoverState();
    }
    if (_isElementInteractionDisabledForCurrentTool) {
      _updateCursorIfChanged(_idleCursorForCurrentTool);
      return _clearHoverState();
    }

    // Shared arrow-handle lookup (used by both cursor and hover).
    final arrowHandle = _resolveArrowPointHandleForPosition(
      state: state,
      position: position,
    );
    if (arrowHandle != null) {
      final arrowCursor =
          _resolveArrowHandleCursor(state: state, handle: arrowHandle) ??
          _cursorResolver.grabCursor();
      _updateCursorIfChanged(arrowCursor);
      return _applyHoverState(
        selectionId: null,
        bindingId: null,
        arrowHandle: arrowHandle,
      );
    }

    // Shared hit test (computed once, used for both cursor and hover).
    final stateView = _buildStateView(state);
    final selectionConfig = _resolveSelectionConfigForInput(state);
    final hitResult = draw_hit_test.hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: widget.store.context.elementRegistry,
      filterTypeId: widget.currentToolTypeId,
    );

    // --- derive cursor from shared hitResult ---
    MouseCursor nextCursor;
    if (_shouldForceDefaultCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    )) {
      nextCursor = _idleCursorForCurrentTool;
    } else if (_shouldShowTextCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    )) {
      nextCursor = SystemMouseCursors.text;
    } else if (!hitResult.isHit) {
      nextCursor = _idleCursorForCurrentTool;
    } else {
      nextCursor = _cursorResolver.resolveForHitTest(hitResult);
    }
    _updateCursorIfChanged(nextCursor);

    // --- derive hover selection from shared hitResult ---
    String? hoverId;
    final canHover =
        _isPointerInside &&
        _middlePanPointerId == null &&
        interaction is! EditingState &&
        interaction is! CreatingState &&
        interaction is! BoxSelectingState &&
        interaction is! TextEditingState;
    if (canHover && !hitResult.isHandleHit) {
      final elementId = hitResult.elementId;
      if (elementId != null &&
          !state.domain.selection.selectedIds.contains(elementId)) {
        hoverId = elementId;
      }
    }

    String? bindingId;
    if (hoverId == null) {
      bindingId = _resolveHoverBindingElementId(
        state: state,
        position: position,
      );
    }

    return _applyHoverState(
      selectionId: hoverId,
      bindingId: bindingId,
      arrowHandle: null,
    );
  }

  MouseCursor? _resolveInteractionCursorWithoutHitTest(
    InteractionState interaction,
  ) {
    if (interaction is CreatingState || interaction is BoxSelectingState) {
      return _idleCursorForCurrentTool;
    }
    return null;
  }

  bool _clearHoverState() =>
      _applyHoverState(selectionId: null, bindingId: null, arrowHandle: null);

  bool _applyHoverState({
    required String? selectionId,
    required String? bindingId,
    required ArrowPointHandle? arrowHandle,
  }) {
    if (_hoveredSelectionElementId == selectionId &&
        _hoveredBindingElementId == bindingId &&
        _hoveredArrowHandle == arrowHandle) {
      return false;
    }
    setState(() {
      _hoveredSelectionElementId = selectionId;
      _hoveredBindingElementId = bindingId;
      _hoveredArrowHandle = arrowHandle;
    });
    return true;
  }

  String? _resolveHoverBindingElementId({
    required DrawState state,
    required DrawPoint position,
  }) {
    if (!_isPointerInside || _middlePanPointerId != null) {
      return null;
    }
    if (widget.currentToolTypeId != ArrowData.typeIdToken &&
        widget.currentToolTypeId != LineData.typeIdToken) {
      return null;
    }
    final interaction = state.application.interaction;
    if (interaction is EditingState ||
        interaction is CreatingState ||
        interaction is BoxSelectingState ||
        interaction is TextEditingState) {
      return null;
    }

    final config = widget.store.config;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: _currentModifiers.control,
    );
    if (!_shouldPreviewArrowBinding(
      snapConfig: config.snap,
      snappingMode: snappingMode,
    )) {
      return null;
    }

    final zoom = state.application.view.camera.zoom;
    final effectiveZoom = _doubleEquals(zoom, 0) ? 1.0 : zoom;
    final bindingDistance = config.snap.arrowBindingDistance / effectiveZoom;
    if (bindingDistance <= 0) {
      return null;
    }
    if (!state.domain.document.hasArrowBindableElements) {
      return null;
    }

    final searchDistance = ArrowBindingUtils.resolveBindingSearchDistance(
      bindingDistance,
    );
    final targets = _resolveBindingTargets(state, position, searchDistance);
    if (targets.isEmpty) {
      return null;
    }

    final arrowStyle = config.arrowStyle;
    final candidate = arrowStyle.arrowType == ArrowType.elbow
        ? ArrowBindingUtils.resolveElbowBindingCandidate(
            worldPoint: position,
            targets: targets,
            snapDistance: bindingDistance,
            hasArrowhead: arrowStyle.startArrowhead != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBindingCandidate(
            worldPoint: position,
            targets: targets,
            snapDistance: bindingDistance,
          );
    if (candidate == null) {
      return null;
    }
    return candidate.binding.elementId;
  }

  bool _shouldPreviewArrowBinding({
    required SnapConfig snapConfig,
    required SnappingMode snappingMode,
  }) {
    if (!snapConfig.enableArrowBinding) {
      return false;
    }
    if (snappingMode == SnappingMode.grid) {
      return false;
    }
    if (snapConfig.enabled && snappingMode == SnappingMode.none) {
      return false;
    }
    return true;
  }

  List<ElementState> _resolveBindingTargets(
    DrawState state,
    DrawPoint position,
    double distance,
  ) {
    final document = state.domain.document;
    final targets = <ElementState>[];
    document.visitElementsAtPointTopDown(position, distance, (element) {
      if (element.opacity <= 0 ||
          !ArrowBindingUtils.isBindableTarget(element)) {
        return true;
      }
      targets.add(element);
      return true;
    });
    return targets;
  }

  ArrowPointHandle? _resolveArrowPointHandleForPosition({
    required DrawState state,
    required DrawPoint position,
  }) {
    if (!_isPointerInside || _middlePanPointerId != null) {
      return null;
    }
    final interaction = state.application.interaction;
    if (interaction is EditingState ||
        interaction is CreatingState ||
        interaction is BoxSelectingState ||
        interaction is TextEditingState) {
      return null;
    }

    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.length != 1) {
      return null;
    }
    final element = state.domain.document.getElementById(selectedIds.first);
    if (element == null || element.data is! ArrowLikeData) {
      return null;
    }

    final stateView = _buildStateView(state);
    final selectionConfig = _resolveSelectionConfigForInput(state);
    final hitRadius = selectionConfig.interaction.handleTolerance;
    // Apply multiplier for arrow point handles to make them larger
    final handleSize =
        selectionConfig.render.controlPointSize *
        ConfigDefaults.arrowPointSizeMultiplier;
    final loopThreshold = hitRadius * 1.5;
    return ArrowPointUtils.hitTest(
      element: stateView.effectiveElement(element),
      position: position,
      hitRadius: hitRadius,
      loopThreshold: loopThreshold,
      handleSize: handleSize,
    );
  }

  ArrowPointHandle? _resolveActiveArrowHandle(DrawStateView stateView) {
    final interaction = stateView.state.application.interaction;
    if (interaction is! EditingState) {
      return null;
    }
    if (interaction.context is! ArrowPointEditContext) {
      return null;
    }
    final context = interaction.context as ArrowPointEditContext;
    var kind = context.pointKind;
    var index = context.pointIndex;
    final transform = interaction.currentTransform;
    if (transform is ArrowPointTransform && kind == ArrowPointKind.addable) {
      if (transform.didInsert) {
        kind = ArrowPointKind.turning;
        index = context.pointIndex + 1;
      } else if (transform.activeIndex != null) {
        index = transform.activeIndex!;
      }
    }
    var isFixed = false;
    final element = stateView.state.domain.document.getElementById(
      context.elementId,
    );
    final effectiveElement = element == null
        ? null
        : stateView.effectiveElement(element);
    final data = effectiveElement?.data;
    if (data is ArrowLikeData &&
        data.arrowType == ArrowType.elbow &&
        kind == ArrowPointKind.addable) {
      final segmentIndex = index + 1;
      isFixed =
          data.fixedSegments?.any((segment) => segment.index == segmentIndex) ??
          false;
    }
    return ArrowPointHandle(
      elementId: context.elementId,
      kind: kind,
      index: index,
      position: DrawPoint.zero,
      isFixed: isFixed,
    );
  }

  bool _isArrowDeleteIndicatorVisible(DrawStateView stateView) {
    final interaction = stateView.state.application.interaction;
    if (interaction is! EditingState) {
      return false;
    }
    final transform = interaction.currentTransform;
    return transform is ArrowPointTransform && transform.shouldDelete;
  }

  MouseCursor? _resolveArrowHandleCursor({
    required DrawState state,
    required ArrowPointHandle handle,
  }) {
    if (handle.kind != ArrowPointKind.addable) {
      return null;
    }
    final element = state.domain.document.getElementById(handle.elementId);
    if (element == null || element.data is! ArrowLikeData) {
      return null;
    }
    final data = element.data as ArrowLikeData;
    if (data.arrowType != ArrowType.elbow) {
      return null;
    }
    final points = ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
    final startIndex = handle.index;
    final endIndex = startIndex + 1;
    if (startIndex < 0 || endIndex >= points.length) {
      return null;
    }
    final start = points[startIndex];
    final end = points[endIndex];
    final dx = (start.dx - end.dx).abs();
    final dy = (start.dy - end.dy).abs();
    final isHorizontal = dy <= dx;
    return isHorizontal
        ? SystemMouseCursors.resizeUp
        : SystemMouseCursors.resizeLeft;
  }

  SelectionConfig _resolveSelectionConfig(DrawState state) {
    final selectionConfig = widget.store.config.selection;
    if (!_isSingleTextSelection(state)) {
      return selectionConfig;
    }
    return selectionConfig.copyWith(
      padding: selectionConfig.padding + _textSelectionPaddingBoost,
    );
  }

  SelectionConfig _resolveHoverSelectionConfig() =>
      widget.store.config.selection;

  SelectionConfig _resolveSelectionConfigForInput(DrawState state) {
    final selectionConfig = _resolveSelectionConfig(state);
    final scale = _effectiveScaleFactor();
    final effectiveScale = _doubleEquals(scale, 0) ? 1.0 : scale;
    if (_doubleEquals(effectiveScale, 1)) {
      return selectionConfig;
    }
    final cachedSource = _cachedInputSelectionConfigSource;
    final cachedScale = _cachedInputSelectionScale;
    final cachedConfig = _cachedInputSelectionConfig;
    if (cachedConfig != null &&
        identical(cachedSource, selectionConfig) &&
        cachedScale != null &&
        _doubleEquals(cachedScale, effectiveScale)) {
      return cachedConfig;
    }

    final interaction = selectionConfig.interaction;
    final render = selectionConfig.render;
    final scaled = selectionConfig.copyWith(
      render: render.copyWith(
        strokeWidth: render.strokeWidth / effectiveScale,
        cornerRadius: render.cornerRadius / effectiveScale,
        controlPointSize: render.controlPointSize / effectiveScale,
      ),
      padding: selectionConfig.padding / effectiveScale,
      rotateHandleOffset: selectionConfig.rotateHandleOffset / effectiveScale,
      interaction: interaction.copyWith(
        handleTolerance: interaction.handleTolerance / effectiveScale,
        dragThreshold: interaction.dragThreshold / effectiveScale,
      ),
    );
    _cachedInputSelectionConfigSource = selectionConfig;
    _cachedInputSelectionConfig = scaled;
    _cachedInputSelectionScale = effectiveScale;
    return scaled;
  }

  bool _isSingleTextSelection(DrawState state) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.length != 1) {
      return false;
    }
    final element = state.domain.document.getElementById(selectedIds.first);
    return element?.data is TextData;
  }

  bool _shouldShowTextCursor({
    required DrawState state,
    required DrawPoint position,
    required DrawStateView stateView,
    required draw_hit_test.HitTestResult hitResult,
    required SelectionConfig selectionConfig,
  }) {
    if (hitResult.isHandleHit) {
      return false;
    }

    final interaction = state.application.interaction;
    if (interaction is TextEditingState) {
      if (_isInsideRect(interaction.rect, interaction.rotation, position)) {
        return true;
      }

      final selectionHit = _isSelectionHit(
        stateView: stateView,
        position: position,
        hitResult: hitResult,
        selectionConfig: selectionConfig,
      );
      if (selectionHit) {
        return false;
      }

      final isTextToolActive = widget.currentToolTypeId == TextData.typeIdToken;
      if (!isTextToolActive) {
        return false;
      }
      return _isInsideAnyTextElement(stateView, position);
    }

    final isTextToolActive = widget.currentToolTypeId == TextData.typeIdToken;
    if (isTextToolActive) {
      if (_shouldDeferToSelectionBox(
        stateView: stateView,
        position: position,
        hitResult: hitResult,
        selectionConfig: selectionConfig,
      )) {
        return false;
      }
      return true;
    }

    final isSelectionToolActive =
        widget.currentToolTypeId == null && widget.isSelectionToolActive;
    final isSerialToolActive =
        widget.currentToolTypeId == SerialNumberData.typeIdToken;
    final isSelectionLikeToolActive =
        isSelectionToolActive || isSerialToolActive;
    if (!isSelectionLikeToolActive) {
      return false;
    }

    if (_isShiftPressed) {
      return false;
    }

    if (!state.domain.hasSelection) {
      return false;
    }

    if (_hasMultipleSelectedTextElements(state)) {
      return false;
    }

    return _isInsideSelectedTextElement(stateView, position);
  }

  bool _shouldForceDefaultCursor({
    required DrawState state,
    required DrawPoint position,
    required DrawStateView stateView,
    required draw_hit_test.HitTestResult hitResult,
    required SelectionConfig selectionConfig,
  }) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return false;
    }

    if (_isInsideRect(interaction.rect, interaction.rotation, position)) {
      return false;
    }

    final selectionHit = _isSelectionHit(
      stateView: stateView,
      position: position,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    );
    if (selectionHit) {
      return false;
    }

    final isTextToolActive = widget.currentToolTypeId == TextData.typeIdToken;
    if (!isTextToolActive) {
      return true;
    }

    return !_isInsideAnyTextElement(stateView, position);
  }

  bool _isSelectionHit({
    required DrawStateView stateView,
    required DrawPoint position,
    required draw_hit_test.HitTestResult hitResult,
    required SelectionConfig selectionConfig,
  }) => hitResult.isHandleHit || hitResult.isInSelectionPadding;

  bool _shouldDeferToSelectionBox({
    required DrawStateView stateView,
    required DrawPoint position,
    required draw_hit_test.HitTestResult hitResult,
    required SelectionConfig selectionConfig,
  }) {
    final state = stateView.state;
    if (!state.domain.hasSelection) {
      return false;
    }

    if (!_hasSelectedTextElement(state)) {
      return false;
    }

    if (!stateView.effectiveSelection.hasSelection) {
      return false;
    }

    if (!_isSelectionHit(
      stateView: stateView,
      position: position,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    )) {
      return false;
    }

    return !_isInsideSelectedTextElement(stateView, position);
  }

  bool _hasSelectedTextElement(DrawState state) {
    for (final id in state.domain.selection.selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData) {
        return true;
      }
    }
    return false;
  }

  bool _hasMultipleSelectedTextElements(DrawState state) {
    var count = 0;
    for (final id in state.domain.selection.selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData) {
        count += 1;
        if (count > 1) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isInsideSelectedTextElement(
    DrawStateView stateView,
    DrawPoint position,
  ) {
    final selectedIds = stateView.state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return false;
    }
    final registry = widget.store.context.elementRegistry;
    final elements = stateView.elements;
    for (var i = elements.length - 1; i >= 0; i--) {
      final element = stateView.effectiveElement(elements[i]);
      if (!selectedIds.contains(element.id)) {
        continue;
      }
      if (element.data is! TextData) {
        continue;
      }
      final definition = registry.getDefinition(element.typeId);
      final hitTester = definition?.hitTester;
      final isHit =
          hitTester?.hitTest(element: element, position: position) ??
          _isInsideRect(element.rect, element.rotation, position);
      if (isHit) {
        return true;
      }
    }
    return false;
  }

  bool _isInsideAnyTextElement(DrawStateView stateView, DrawPoint position) {
    final registry = widget.store.context.elementRegistry;
    final elements = stateView.elements;
    for (var i = elements.length - 1; i >= 0; i--) {
      final element = stateView.effectiveElement(elements[i]);
      if (element.data is! TextData) {
        continue;
      }
      final definition = registry.getDefinition(element.typeId);
      final hitTester = definition?.hitTester;
      final isHit =
          hitTester?.hitTest(element: element, position: position) ??
          _isInsideRect(element.rect, element.rotation, position);
      if (isHit) {
        return true;
      }
    }
    return false;
  }

  bool _isInsideRect(DrawRect rect, double rotation, DrawPoint position) {
    final local = rotation == 0
        ? position
        : ElementSpace(
            rotation: rotation,
            origin: rect.center,
          ).fromWorld(position);
    return local.x >= rect.minX &&
        local.x <= rect.maxX &&
        local.y >= rect.minY &&
        local.y <= rect.maxY;
  }

  MouseCursor _resolveCursorForState(DrawState state, DrawPoint? position) {
    if (_middlePanPointerId != null) {
      return _draggingCursor;
    }
    final interaction = state.application.interaction;
    final lockedCursor = _cursorResolver.resolveLockedCursor(interaction);
    if (lockedCursor != null) {
      return lockedCursor;
    }
    final interactionCursor = _resolveInteractionCursorWithoutHitTest(
      interaction,
    );
    if (interactionCursor != null) {
      return interactionCursor;
    }

    if (!_isPointerInside || position == null) {
      return _idleCursorForCurrentTool;
    }
    if (_isElementInteractionDisabledForCurrentTool) {
      return _idleCursorForCurrentTool;
    }

    final arrowHandle = _resolveArrowPointHandleForPosition(
      state: state,
      position: position,
    );
    if (arrowHandle != null) {
      return _resolveArrowHandleCursor(state: state, handle: arrowHandle) ??
          _cursorResolver.grabCursor();
    }

    final stateView = _buildStateView(state);
    final selectionConfig = _resolveSelectionConfigForInput(state);
    final hitResult = draw_hit_test.hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: widget.store.context.elementRegistry,
      filterTypeId: widget.currentToolTypeId,
    );
    if (_shouldForceDefaultCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    )) {
      return _idleCursorForCurrentTool;
    }
    if (_shouldShowTextCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
      selectionConfig: selectionConfig,
    )) {
      return SystemMouseCursors.text;
    }
    if (!hitResult.isHit) {
      return _idleCursorForCurrentTool;
    }
    return _cursorResolver.resolveForHitTest(hitResult);
  }

  void _syncWatermarkLayerState(DrawState state, {double? scaleFactor}) {
    _watermarkLayerController.update(
      WatermarkCanvasLayerState(
        camera: state.application.view.camera,
        scaleFactor: scaleFactor ?? _effectiveScaleFactor(),
        config: state.domain.document.globalElements.watermark,
      ),
    );
  }

  bool _isWatermarkOnlyStateChange(DrawState previous, DrawState next) {
    if (identical(previous, next)) {
      return false;
    }

    if (previous.application.view != next.application.view ||
        previous.application.interaction != next.application.interaction ||
        previous.application.selectionOverlay !=
            next.application.selectionOverlay ||
        previous.domain.selection != next.domain.selection) {
      return false;
    }

    final previousDocument = previous.domain.document;
    final nextDocument = next.domain.document;

    if (previousDocument.elementsVersion != nextDocument.elementsVersion ||
        !identical(previousDocument.elements, nextDocument.elements)) {
      return false;
    }

    final previousGlobals = previousDocument.globalElements;
    final nextGlobals = nextDocument.globalElements;

    if (previousGlobals.highlightMask != nextGlobals.highlightMask) {
      return false;
    }

    return previousGlobals.watermark != nextGlobals.watermark;
  }

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.0001;

  bool get _isElementInteractionDisabledForCurrentTool =>
      widget.isEraserToolActive ||
      (widget.currentToolTypeId == null && !widget.isSelectionToolActive);

  MouseCursor get _idleCursorForCurrentTool => widget.isEraserToolActive
      ? SystemMouseCursors.none
      : _isElementInteractionDisabledForCurrentTool
      ? SystemMouseCursors.basic
      : _defaultCursor;

  DrawStateView _buildStateView(DrawState state) {
    final cachedState = _cachedState;
    final cachedView = _cachedStateView;
    if (cachedView != null && identical(cachedState, state)) {
      return cachedView;
    }
    final nextView = _stateViewBuilder.build(state);
    _cachedState = state;
    _cachedStateView = nextView;
    return nextView;
  }

  Widget? _buildTextEditorOverlay({
    required DrawState state,
    required double scaleFactor,
    Locale? locale,
  }) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      _disposeTextEditor();
      return null;
    }

    _syncTextEditor(interaction);

    final rect = interaction.rect;
    final topLeft = _coords.worldToScreen(
      DrawPoint(x: rect.minX, y: rect.minY),
    );
    final layoutWidth = rect.width;
    final height = rect.height;
    if (layoutWidth <= 0 || height <= 0) {
      _editingTextLayout = null;
      _clearEditingPainterLayoutCache();
      return null;
    }
    // RenderEditable subtracts a caret margin from maxWidth when laying out.
    final fieldWidth = layoutWidth + textCaretMargin;
    final data = interaction.draftData;
    final opacity = interaction.opacity;
    final textOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final textColor = data.color.withValues(alpha: textOpacity);
    final textStyle = buildTextStyle(
      data: data,
      colorOverride: textColor,
      locale: locale,
    );
    // Render text on the canvas; keep the TextField only for caret/input.
    final inputTextStyle = textStyle.copyWith(color: Colors.transparent);

    final layout = layoutText(
      data: data,
      maxWidth: layoutWidth,
      minWidth: layoutWidth,
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );
    _editingTextLayout = layout;
    _invalidateEditingPainterLayoutIfNeeded(
      data: data,
      layoutWidth: layoutWidth,
      locale: locale,
    );
    final textHeight = layout.size.height;
    final verticalOffset = _resolveVerticalOffset(
      containerHeight: height,
      textHeight: textHeight,
      align: data.verticalAlign,
    );

    _applyInitialSelection(
      interaction: interaction,
      rect: rect,
      layout: layout,
      verticalOffset: verticalOffset,
    );

    Widget textField = TextField(
      controller: _textController,
      focusNode: _textFocusNode,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      maxLines: null,
      style: inputTextStyle,
      strutStyle: resolveTextStrutStyle(textStyle),
      textAlign: _toFlutterAlign(data.horizontalAlign),
      textDirection: TextDirection.ltr,
      clipBehavior: Clip.none,
      // Avoid InputDecorator so RenderEditable uses tight
      // constraints, keeping vertical caret runs valid.
      decoration: null,
      cursorColor: textColor,
      cursorWidth: textCursorWidth,
    );
    textField = Listener(
      onPointerDown: (_) => _resetVerticalCaretRun(),
      child: textField,
    );

    return Positioned(
      left: topLeft.x,
      top: topLeft.y,
      child: Transform.scale(
        scale: scaleFactor,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: interaction.rotation,
          child: SizedBox(
            width: layoutWidth,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: verticalOffset,
                  width: fieldWidth,
                  height: textHeight,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textLayoutTextScaler),
                    child: DefaultTextHeightBehavior(
                      textHeightBehavior: textLayoutHeightBehavior,
                      child: textField,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncTextEditor(TextEditingState interaction) {
    final controller = _textController;
    if (controller == null || _editingElementId != interaction.elementId) {
      _disposeTextEditor();
      _textController = TextEditingController(text: interaction.draftData.text)
        ..addListener(_handleTextControllerChanged);
      _editingElementId = interaction.elementId;
      _initialSelectionApplied = false;
      _clearEditingPainterLayoutCache();
      _resetVerticalCaretRun();
    } else if (!_suppressTextControllerChange &&
        controller.text != interaction.draftData.text) {
      _suppressTextControllerChange = true;
      controller.text = interaction.draftData.text;
      _suppressTextControllerChange = false;
      _clearEditingPainterLayoutCache();
    }

    _scheduleTextFocus();
  }

  void _disposeTextEditor() {
    final controller = _textController;
    if (controller != null) {
      controller
        ..removeListener(_handleTextControllerChanged)
        ..dispose();
      _textController = null;
    }
    _editingElementId = null;
    _initialSelectionApplied = false;
    _editingTextLayout = null;
    _clearEditingPainterLayoutCache();
    _resetVerticalCaretRun();
    if (_textFocusNode.hasFocus) {
      _textFocusNode.unfocus();
    }
  }

  void _scheduleTextFocus() {
    if (_textFocusScheduled || _textFocusNode.hasFocus) {
      return;
    }
    _textFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocusScheduled = false;
      if (!mounted) {
        return;
      }
      if (widget.store.state.application.interaction is TextEditingState) {
        _textFocusNode.requestFocus();
      }
    });
  }

  void _invalidateEditingPainterLayoutIfNeeded({
    required TextData data,
    required double layoutWidth,
    required Locale? locale,
  }) {
    final nextKey = _EditingPainterLayoutKey(
      text: data.text,
      fontSize: data.fontSize,
      fontFamily: data.fontFamily,
      horizontalAlign: data.horizontalAlign,
      layoutWidth: layoutWidth,
      localeTag: locale?.toLanguageTag(),
    );
    if (_editingPainterLayoutKey == nextKey) {
      return;
    }
    _editingPainterLayoutKey = nextKey;
    _editingPainterLayout = null;
  }

  PainterTextLayoutMetrics? _resolveEditingPainterLayout() {
    final interaction = widget.store.state.application.interaction;
    if (interaction is! TextEditingState) {
      return null;
    }
    final layoutWidth = interaction.rect.width;
    if (layoutWidth <= 0) {
      return null;
    }
    final locale = Localizations.maybeLocaleOf(context);
    final nextKey = _EditingPainterLayoutKey(
      text: interaction.draftData.text,
      fontSize: interaction.draftData.fontSize,
      fontFamily: interaction.draftData.fontFamily,
      horizontalAlign: interaction.draftData.horizontalAlign,
      layoutWidth: layoutWidth,
      localeTag: locale?.toLanguageTag(),
    );
    final cachedLayout = _editingPainterLayout;
    if (cachedLayout != null && _editingPainterLayoutKey == nextKey) {
      return cachedLayout;
    }

    final layout = layoutTextWithPainter(
      data: interaction.draftData,
      maxWidth: layoutWidth,
      minWidth: layoutWidth,
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );
    _editingPainterLayout = layout;
    _editingPainterLayoutKey = nextKey;
    return layout;
  }

  void _clearEditingPainterLayoutCache() {
    _editingPainterLayout = null;
    _editingPainterLayoutKey = null;
  }

  void _handleTextControllerChanged() {
    if (_suppressTextControllerChange) {
      return;
    }
    final controller = _textController;
    if (controller == null) {
      return;
    }
    final interaction = widget.store.state.application.interaction;
    if (interaction is! TextEditingState) {
      return;
    }
    final nextText = controller.text;
    if (nextText == interaction.draftData.text) {
      return;
    }
    _clearEditingPainterLayoutCache();
    _resetVerticalCaretRun();
    unawaited(widget.store.dispatch(UpdateTextEdit(text: nextText)));
  }

  void _resetVerticalCaretRun() {
    _lastVerticalSelection = null;
    _verticalCaretX = null;
  }

  KeyEventResult _handleTextFocusKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;
    final isArrowUp = logicalKey == LogicalKeyboardKey.arrowUp;
    final isArrowDown = logicalKey == LogicalKeyboardKey.arrowDown;
    final isPageUp = logicalKey == LogicalKeyboardKey.pageUp;
    final isPageDown = logicalKey == LogicalKeyboardKey.pageDown;
    if (isArrowUp || isArrowDown || isPageUp || isPageDown) {
      final interaction = widget.store.state.application.interaction;
      if (interaction is! TextEditingState) {
        return KeyEventResult.ignored;
      }
      if (interaction.draftData.horizontalAlign == TextHorizontalAlign.left) {
        return KeyEventResult.ignored;
      }
      // Work around VerticalCaretMovementRun assertions for non-left alignment.
      final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
      final isShiftPressed =
          keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          keysPressed.contains(LogicalKeyboardKey.shiftRight) ||
          keysPressed.contains(LogicalKeyboardKey.shift);
      final layout = _editingTextLayout;
      _handleVerticalCaretMovement(
        forward: isArrowDown || isPageDown,
        collapseSelection: !isShiftPressed,
        pageOffset: (isPageUp || isPageDown) && layout != null
            ? layout.size.height
            : null,
      );
      return KeyEventResult.handled;
    }

    _resetVerticalCaretRun();
    return KeyEventResult.ignored;
  }

  void _handleVerticalCaretMovement({
    required bool forward,
    required bool collapseSelection,
    double? pageOffset,
  }) {
    final controller = _textController;
    final layout = _resolveEditingPainterLayout();
    if (controller == null || layout == null) {
      return;
    }
    final selection = controller.selection;
    if (!selection.isValid) {
      return;
    }

    final lineMetrics = layout.lineMetrics;
    if (lineMetrics.isEmpty) {
      return;
    }

    final textLength = controller.text.length;
    final currentPosition = selection.extent;
    final caretPrototype = Rect.fromLTWH(
      0,
      0,
      textCursorWidth,
      layout.lineHeight,
    );

    final caretOffset = layout.painter.getOffsetForCaret(
      currentPosition,
      caretPrototype,
    );
    if (_lastVerticalSelection == null ||
        _lastVerticalSelection != selection ||
        _verticalCaretX == null) {
      _verticalCaretX = caretOffset.dx;
    }

    final currentLineIndex = _lineIndexForCaretOffset(
      caretOffset.dy,
      lineMetrics,
    );
    int targetLineIndex;
    if (pageOffset != null) {
      final currentBaseline = lineMetrics[currentLineIndex].baseline;
      final targetBaseline =
          currentBaseline + (forward ? pageOffset : -pageOffset);
      targetLineIndex = _lineIndexForBaseline(
        baseline: targetBaseline,
        lineMetrics: lineMetrics,
        forward: forward,
      );
    } else {
      targetLineIndex = currentLineIndex + (forward ? 1 : -1);
    }

    TextPosition newExtent;
    if (targetLineIndex < 0) {
      newExtent = const TextPosition(offset: 0);
    } else if (targetLineIndex >= lineMetrics.length) {
      newExtent = TextPosition(offset: textLength);
    } else {
      final targetBaseline = lineMetrics[targetLineIndex].baseline;
      final targetOffset = Offset(_verticalCaretX ?? 0, targetBaseline);
      newExtent = layout.painter.getPositionForOffset(targetOffset);
    }

    final nextSelection = collapseSelection
        ? TextSelection.collapsed(offset: newExtent.offset)
        : selection.extendTo(newExtent);
    controller.selection = nextSelection;
    _lastVerticalSelection = nextSelection;
  }

  int _lineIndexForCaretOffset(double caretDy, List<LineMetrics> lineMetrics) {
    for (var i = 0; i < lineMetrics.length; i++) {
      if (lineMetrics[i].baseline > caretDy) {
        return i;
      }
    }
    return lineMetrics.isEmpty ? 0 : lineMetrics.length - 1;
  }

  int _lineIndexForBaseline({
    required double baseline,
    required List<LineMetrics> lineMetrics,
    required bool forward,
  }) {
    if (forward) {
      for (var i = 0; i < lineMetrics.length; i++) {
        if (lineMetrics[i].baseline >= baseline) {
          return i;
        }
      }
      return lineMetrics.length - 1;
    }

    for (var i = lineMetrics.length - 1; i >= 0; i--) {
      if (lineMetrics[i].baseline <= baseline) {
        return i;
      }
    }
    return 0;
  }

  void _applyInitialSelection({
    required TextEditingState interaction,
    required DrawRect rect,
    required TextLayoutMetrics layout,
    required double verticalOffset,
  }) {
    if (_initialSelectionApplied) {
      return;
    }
    final controller = _textController;
    if (controller == null) {
      return;
    }
    final cursorWorld = interaction.initialCursorPosition;
    if (cursorWorld == null) {
      _initialSelectionApplied = true;
      return;
    }

    final localWorld = interaction.rotation == 0
        ? cursorWorld
        : ElementSpace(
            rotation: interaction.rotation,
            origin: rect.center,
          ).fromWorld(cursorWorld);

    final localDx = localWorld.x - rect.minX;
    final localDy = localWorld.y - rect.minY;
    final offset = Offset(localDx, localDy - verticalOffset);
    final position = layout.paragraph.getPositionForOffset(offset);
    final textLength = controller.text.length;
    var nextOffset = position.offset;
    if (nextOffset < 0) {
      nextOffset = 0;
    } else if (nextOffset > textLength) {
      nextOffset = textLength;
    }
    controller.selection = TextSelection.collapsed(offset: nextOffset);
    _initialSelectionApplied = true;
  }

  TextAlign _toFlutterAlign(TextHorizontalAlign align) {
    switch (align) {
      case TextHorizontalAlign.left:
        return TextAlign.left;
      case TextHorizontalAlign.center:
        return TextAlign.center;
      case TextHorizontalAlign.right:
        return TextAlign.right;
    }
  }

  double _resolveVerticalOffset({
    required double containerHeight,
    required double textHeight,
    required TextVerticalAlign align,
  }) {
    var offset = 0.0;
    switch (align) {
      case TextVerticalAlign.top:
        offset = 0;
      case TextVerticalAlign.center:
        offset = (containerHeight - textHeight) / 2;
      case TextVerticalAlign.bottom:
        offset = containerHeight - textHeight;
    }
    if (offset.isNaN || offset.isInfinite || offset < 0) {
      return 0;
    }
    return offset;
  }

  void _handleStateChange(DrawState state) {
    final previousState = _lastObservedState;
    _lastObservedState = state;
    _syncWatermarkLayerState(state);

    if (previousState != null &&
        _isWatermarkOnlyStateChange(previousState, state)) {
      return;
    }

    final position = _lastPointerPosition;
    if (position != null && _isPointerInside) {
      // Use the combined path when a pointer position is available.
      if (!mounted) {
        // When not mounted we cannot call setState, so compute
        // cursor and hover state directly.
        _cursor = _resolveCursorForState(state, position);
        _hoveredSelectionElementId = null;
        _hoveredBindingElementId = _resolveHoverBindingElementId(
          state: state,
          position: position,
        );
        _hoveredArrowHandle = _resolveArrowPointHandleForPosition(
          state: state,
          position: position,
        );
        return;
      }
      final hoverStateChanged = _updateCursorAndHoverForPosition(position);
      // Always rebuild on state changes so the canvas picks up new
      // interaction state (e.g. creating element with appended points).
      // _updateCursorAndHoverForPosition only calls setState when hover
      // values change, which is not enough for live creation updates.
      if (!hoverStateChanged) {
        setState(() {});
      }
      return;
    }
    final cursor = _resolveCursorForState(state, position);
    if (!mounted) {
      _cursor = cursor;
      _hoveredSelectionElementId = null;
      _hoveredBindingElementId = null;
      _hoveredArrowHandle = null;
      return;
    }
    _updateCursorIfChanged(cursor);
    final hoverStateChanged = _clearHoverState();
    // Rebuild unconditionally so the canvas reflects the new state.
    if (!hoverStateChanged) {
      setState(() {});
    }
  }

  void _handleConfigChange(DrawConfig _) {
    if (!mounted) {
      return;
    }
    _cachedInputSelectionConfigSource = null;
    _cachedInputSelectionConfig = null;
    _cachedInputSelectionScale = null;

    final position = _lastPointerPosition;
    late final bool hoverStateChanged;
    if (position != null && _isPointerInside) {
      hoverStateChanged = _updateCursorAndHoverForPosition(position);
    } else {
      _updateCursorIfChanged(
        _resolveCursorForState(widget.store.state, position),
      );
      hoverStateChanged = _clearHoverState();
    }
    if (!hoverStateChanged) {
      setState(() {});
    }
  }

  void _handleTextRenderingCacheInvalidation() {
    if (!mounted) {
      return;
    }
    _editingTextLayout = null;
    _clearEditingPainterLayoutCache();
    unawaited(_refreshAutoResizeTextLayoutsAfterFontLoad());
    setState(() {});
  }

  void _handleSystemFontsChange() {
    invalidateTextRenderingCaches();
  }

  Future<void> _refreshAutoResizeTextLayoutsAfterFontLoad() async {
    if (_isRefreshingAutoResizeTextLayoutsAfterFontLoad) {
      return;
    }
    _isRefreshingAutoResizeTextLayoutsAfterFontLoad = true;
    try {
      await widget.store.dispatch(
        const RefreshAutoResizeTextLayoutsAfterFontLoad(),
      );
    } on Object catch (error, stackTrace) {
      widget.store.context.log.render.error(
        'Failed to refresh auto-resize text layouts after font load',
        error,
        stackTrace,
      );
    } finally {
      _isRefreshingAutoResizeTextLayoutsAfterFontLoad = false;
    }
  }

  void _updateCursorIfChanged(MouseCursor nextCursor) {
    if (_cursor == nextCursor) {
      return;
    }
    _cursor = nextCursor;
    if (mounted) {
      _cursorNotifier.value = nextCursor;
    }
  }

  void _updateToolPlugins({
    required ElementTypeId<ElementData>? toolTypeId,
    required bool isSelectionToolActive,
  }) {
    final createPlugin = _pluginCoordinator.registry.getPlugin('create');
    if (createPlugin is CreatePlugin) {
      createPlugin.currentToolTypeId = toolTypeId;
    }
    final textPlugin = _pluginCoordinator.registry.getPlugin('text_tool');
    if (textPlugin is TextToolPlugin) {
      textPlugin
        ..currentToolTypeId = toolTypeId
        ..isSelectionToolActive = isSelectionToolActive;
    }
    final selectPlugin = _pluginCoordinator.registry.getPlugin('select');
    if (selectPlugin is SelectPlugin) {
      selectPlugin
        ..currentToolTypeId = toolTypeId
        ..isSelectionToolActive = isSelectionToolActive;
    }
  }

  Future<void> _resetInteractionForToolChange() async {
    _pointerMoveDispatcher.reset();
    final interaction = widget.store.state.application.interaction;
    if (interaction is TextEditingState) {
      await widget.store.dispatch(
        FinishTextEdit(
          elementId: interaction.elementId,
          text: interaction.draftData.text,
          isNew: interaction.isNew,
        ),
      );
    } else if (interaction is CreatingState) {
      await widget.store.dispatch(const CancelCreateElement());
    } else if (interaction is EditingState) {
      await widget.store.dispatch(const CancelEdit());
    } else if (interaction is BoxSelectingState) {
      await widget.store.dispatch(const CancelBoxSelect());
    } else if (interaction is DragPendingState) {
      await widget.store.dispatch(const ClearDragPending());
    }

    await widget.store.dispatch(const ClearSelection());
  }
}

@immutable
class _EditingPainterLayoutKey {
  const _EditingPainterLayoutKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.layoutWidth,
    required this.localeTag,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final double layoutWidth;
  final String? localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EditingPainterLayoutKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.layoutWidth == layoutWidth &&
          other.localeTag == localeTag;

  @override
  int get hashCode => Object.hash(
    text,
    fontSize,
    fontFamily,
    horizontalAlign,
    layoutWidth,
    localeTag,
  );
}
