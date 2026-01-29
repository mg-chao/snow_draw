import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextLayoutMetrics;

import '../../draw/actions/actions.dart';
import '../../draw/config/draw_config.dart';
import '../../draw/core/coordinates/element_space.dart';
import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/elements/core/element_data.dart';
import '../../draw/elements/core/element_type_id.dart';
import '../../draw/elements/types/arrow/arrow_data.dart';
import '../../draw/elements/types/arrow/arrow_geometry.dart';
import '../../draw/elements/types/arrow/arrow_points.dart';
import '../../draw/elements/types/rectangle/rectangle_data.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/elements/types/text/text_layout.dart';
import '../../draw/events/event_bus.dart';
import '../../draw/events/state_events.dart';
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
import 'cursor_resolver.dart';
import 'dynamic_canvas_painter.dart';
import 'grid_shader_painter.dart';
import 'rectangle_shader_manager.dart';
import 'render_keys.dart';
import 'static_canvas_painter.dart';

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
    this.middlewares,
    this.customPlugins,
    this.enableDebugLogging = false,
    this.enablePerformanceMonitoring = false,
  });
  final Size size;
  final double scaleFactor;
  final DrawStore store;
  final ElementTypeId<ElementData>? currentToolTypeId;

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

class _PluginDrawCanvasState extends State<PluginDrawCanvas> {
  static const double _textSelectionPaddingBoost = 16;
  static const _strokeWidthSteps = [2.0, 4.0, 7.0];
  static const _fontSizeSteps = [16.0, 21.0, 27.0, 42.0];
  static const MouseCursor _defaultCursor = SystemMouseCursors.precise;
  static const MouseCursor _draggingCursor = SystemMouseCursors.grabbing;

  StreamSubscription<DrawEvent>? _eventSubscription;
  StreamSubscription<DrawConfig>? _configSubscription;
  final _focusNode = FocusNode();
  late final FocusNode _textFocusNode;
  TextEditingController? _textController;
  String? _editingElementId;
  var _suppressTextControllerChange = false;
  var _initialSelectionApplied = false;
  var _textFocusScheduled = false;
  TextLayoutMetrics? _editingTextLayout;
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
  ArrowPointHandle? _hoveredArrowHandle;
  final _activePointerIds = <int>{};
  int? _middlePanPointerId;
  Offset? _lastMiddlePanPosition;

  CoordinateService? _coordinateService;
  late PluginInputCoordinator _pluginCoordinator;
  late DrawStateViewBuilder _stateViewBuilder;
  DrawState? _cachedState;
  DrawStateView? _cachedStateView;

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
    _textFocusNode = FocusNode(onKeyEvent: _handleTextFocusKeyEvent);
    unawaited(_recreatePluginCoordinator());
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: widget.store.context.editOperations,
    );

    // Preload GPU shaders for optimal first-frame performance.
    unawaited(GridShaderManager.instance.load());
    unawaited(RectangleShaderManager.instance.load());

    _eventSubscription = widget.store.eventStream.listen(_handleEvent);

    _configSubscription = widget.store.configStream.listen((_) {
      if (!mounted) {
        return;
      }
      _updateCursorIfChanged(
        _resolveCursorForState(widget.store.state, _lastPointerPosition),
      );
      _hoveredSelectionElementId = _lastPointerPosition == null
          ? null
          : _resolveHoverSelectionElementId(
              state: widget.store.state,
              position: _lastPointerPosition!,
            );
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(PluginDrawCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRecreateCoordinator =
        oldWidget.store != widget.store ||
        oldWidget.middlewares != widget.middlewares ||
        oldWidget.customPlugins != widget.customPlugins;
    final toolChanged = oldWidget.currentToolTypeId != widget.currentToolTypeId;

    if (shouldRecreateCoordinator) {
      // Dispose old coordinator
      unawaited(_pluginCoordinator.dispose());

      if (oldWidget.store != widget.store) {
        // Unsubscribe from old store events
        unawaited(_eventSubscription?.cancel());
        unawaited(_configSubscription?.cancel());
        _cachedState = null;
        _cachedStateView = null;

        _eventSubscription = widget.store.eventStream.listen(_handleEvent);

        _configSubscription = widget.store.configStream.listen((_) {
          if (!mounted) {
            return;
          }
          _updateCursorIfChanged(
            _resolveCursorForState(widget.store.state, _lastPointerPosition),
          );
          _hoveredSelectionElementId = _lastPointerPosition == null
              ? null
              : _resolveHoverSelectionElementId(
                  state: widget.store.state,
                  position: _lastPointerPosition!,
                );
          setState(() {});
        });

        _stateViewBuilder = DrawStateViewBuilder(
          editOperations: widget.store.context.editOperations,
        );
      }

      // Recreate coordinator
      unawaited(_recreatePluginCoordinator());
    }
    if (toolChanged) {
      unawaited(_resetInteractionForToolChange());
      if (!shouldRecreateCoordinator) {
        _updateToolPlugins(widget.currentToolTypeId);
      }
    }

    _updateCursorIfChanged(
      _resolveCursorForState(widget.store.state, _lastPointerPosition),
    );
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_configSubscription?.cancel());
    _focusNode.dispose();
    _textController?.dispose();
    _textFocusNode.dispose();
    _cursorNotifier.dispose();
    unawaited(_pluginCoordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateView = _buildStateView(widget.store.state);
    final config = widget.store.config;
    final selectionConfig = _resolveSelectionConfig(widget.store.state);
    final scaleFactor = _effectiveScaleFactor();
    final elementRegistry = widget.store.context.elementRegistry;
    final locale = Localizations.maybeLocaleOf(context);
    final textOverlay = _buildTextEditorOverlay(
      state: widget.store.state,
      scaleFactor: scaleFactor,
      locale: locale,
    );
    final dynamicLayerStartIndex = _resolveDynamicLayerStartIndex(stateView);
    final staticPreviewElements = _previewElementsForStatic(
      stateView,
      dynamicLayerStartIndex,
    );
    final dynamicPreviewElements = _previewElementsForDynamic(
      stateView,
      dynamicLayerStartIndex,
    );

    // Build precise render keys for each canvas layer.
    final staticRenderKey = StaticCanvasRenderKey(
      documentVersion: stateView.state.domain.document.elementsVersion,
      camera: stateView.state.application.view.camera,
      previewElementsById: staticPreviewElements,
      dynamicLayerStartIndex: dynamicLayerStartIndex,
      scaleFactor: scaleFactor,
      canvasConfig: config.canvas,
      gridConfig: config.grid,
      elementRegistry: elementRegistry,
      locale: locale,
    );

    final dynamicRenderKey = DynamicCanvasRenderKey(
      creatingElement: _extractCreatingSnapshot(stateView),
      effectiveSelection: stateView.effectiveSelection,
      boxSelectionBounds: _extractBoxSelectionBounds(stateView),
      selectedIds: stateView.selectedIds,
      hoveredElementId: _hoveredSelectionElementId,
      hoveredArrowHandle: _hoveredArrowHandle,
      activeArrowHandle: _resolveActiveArrowHandle(stateView),
      hoverSelectionConfig: _resolveHoverSelectionConfig(),
      snapGuides: stateView.snapGuides,
      documentVersion: stateView.state.domain.document.elementsVersion,
      camera: stateView.state.application.view.camera,
      previewElementsById: dynamicPreviewElements,
      dynamicLayerStartIndex: dynamicLayerStartIndex,
      scaleFactor: scaleFactor,
      selectionConfig: selectionConfig,
      boxSelectionConfig: config.boxSelection,
      snapConfig: config.snap,
      elementRegistry: elementRegistry,
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
          ?textOverlay,
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
    if (dynamicLayerStartIndex == null) {
      return const <String, ElementState>{};
    }
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

  int? _resolveDynamicLayerStartIndex(DrawStateView view) {
    // When creating a new text element, render all existing elements in the
    // static layer so the text element's background appears on top.
    final interaction = view.state.application.interaction;
    if (interaction is TextEditingState && interaction.isNew) {
      return 0;
    }

    final selectedIds = view.selectedIds;
    if (selectedIds.isEmpty) {
      return null;
    }

    final document = view.state.domain.document;
    int? minIndex;
    for (final id in selectedIds) {
      final orderIndex = document.getOrderIndex(id);
      if (orderIndex == null) {
        continue;
      }
      if (minIndex == null || orderIndex < minIndex) {
        minIndex = orderIndex;
      }
    }
    return minIndex;
  }

  /// Extract creating element snapshot from state view.
  CreatingElementSnapshot? _extractCreatingSnapshot(DrawStateView view) {
    final interaction = view.state.application.interaction;
    if (interaction is CreatingState) {
      return CreatingElementSnapshot(
        element: interaction.element,
        currentRect: interaction.currentRect,
      );
    }
    return null;
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
        _isShiftPressed = isPressed;
        return;
      case LogicalKeyboardKey.control:
      case LogicalKeyboardKey.controlLeft:
      case LogicalKeyboardKey.controlRight:
        _isControlPressed = isPressed;
        return;
      case LogicalKeyboardKey.alt:
      case LogicalKeyboardKey.altLeft:
      case LogicalKeyboardKey.altRight:
        _isAltPressed = isPressed;
        return;
      default:
        break;
    }
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
    _recordPointerPosition(event.localPosition);
    if (_isMousePointer(event)) {
      if (_isMiddleMouseButton(event.buttons)) {
        _startMiddlePan(event);
        return;
      }
      if (!_isPrimaryMouseButton(event.buttons)) {
        return;
      }
    }
    _activePointerIds.add(event.pointer);
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerDownInputEvent(
          position: _transformPosition(event.localPosition),
          modifiers: _currentModifiers,
        ),
      ),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    _updateCursorForPosition(position);
    _updateHoverSelectionForPosition(position);
    if (_handleMiddlePanMove(event)) {
      return;
    }
    if (!_activePointerIds.contains(event.pointer)) {
      return;
    }
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerMoveInputEvent(
          position: _transformPosition(event.localPosition),
          modifiers: _currentModifiers,
        ),
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    _recordPointerPosition(event.localPosition);
    if (_middlePanPointerId == event.pointer) {
      _stopMiddlePan();
      _activePointerIds.remove(event.pointer);
      return;
    }
    if (!_activePointerIds.remove(event.pointer)) {
      return;
    }
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerUpInputEvent(
          position: _transformPosition(event.localPosition),
          modifiers: _currentModifiers,
        ),
      ),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _syncKeyboardModifiers();
    if (_middlePanPointerId == event.pointer) {
      _stopMiddlePan();
      _activePointerIds.remove(event.pointer);
      return;
    }
    if (!_activePointerIds.remove(event.pointer)) {
      return;
    }
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerCancelInputEvent(
          position: _transformPosition(event.localPosition),
          modifiers: _currentModifiers,
        ),
      ),
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
    if (toolTypeId == TextData.typeIdToken) {
      _adjustFontSize(event);
      return;
    }
    if (toolTypeId == RectangleData.typeIdToken ||
        toolTypeId == ArrowData.typeIdToken ||
        toolTypeId == null) {
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
    _updateCursorForPosition(position);
    _updateHoverSelectionForPosition(position);
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    _updateCursorForPosition(position);
    _updateHoverSelectionForPosition(position);
    unawaited(
      _pluginCoordinator.handleEvent(
        PointerHoverInputEvent(
          position: position,
          modifiers: _currentModifiers,
        ),
      ),
    );
  }

  void _handlePointerExit(PointerExitEvent event) {
    _isPointerInside = false;
    _lastPointerPosition = null;
    if (_hoveredSelectionElementId != null || _hoveredArrowHandle != null) {
      setState(() {
        _hoveredSelectionElementId = null;
        _hoveredArrowHandle = null;
      });
    }
    final nextCursor = _resolveCursorForState(widget.store.state, null);
    _updateCursorIfChanged(nextCursor);
  }

  DrawPoint _recordPointerPosition(Offset localPosition) {
    _syncKeyboardModifiers();
    final position = _transformPosition(localPosition);
    _lastPointerPosition = position;
    _isPointerInside = true;
    return position;
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
    _middlePanPointerId = null;
    _lastMiddlePanPosition = null;
    _updateCursorIfChanged(
      _resolveCursorForState(widget.store.state, _lastPointerPosition),
    );
    _hoveredSelectionElementId = _lastPointerPosition == null
        ? null
        : _resolveHoverSelectionElementId(
            state: widget.store.state,
            position: _lastPointerPosition!,
          );
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
    final rectangleAverage = _resolveAverageSelectedStrokeWidth(state);
    final base =
        arrowAverage ?? rectangleAverage ?? config.arrowStyle.strokeWidth;

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
  }

  void _adjustFontSize(PointerScrollEvent event) {
    final delta = _resolvePrimaryScrollDelta(event);
    if (delta == null) {
      return;
    }
    final state = widget.store.state;
    final config = widget.store.config;
    final base =
        _resolveEditingFontSize(state) ??
        _resolveAverageSelectedFontSize(state) ??
        config.textStyle.fontSize;

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

  List<String> _resolveTextSelectionIds(DrawState state) {
    final ids = <String>{};
    final selectedIds = state.domain.selection.selectedIds;
    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData) {
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

  void _updateCursorForPosition(DrawPoint position) {
    final nextCursor = _resolveCursorForState(widget.store.state, position);
    _updateCursorIfChanged(nextCursor);
  }

  void _updateHoverSelectionForPosition(DrawPoint position) {
    final nextHover = _resolveHoverSelectionElementId(
      state: widget.store.state,
      position: position,
    );
    final nextArrowHandle = _resolveArrowPointHandleForPosition(
      state: widget.store.state,
      position: position,
    );
    if (_hoveredSelectionElementId == nextHover &&
        _hoveredArrowHandle == nextArrowHandle) {
      return;
    }
    setState(() {
      _hoveredSelectionElementId = nextHover;
      _hoveredArrowHandle = nextArrowHandle;
    });
  }

  String? _resolveHoverSelectionElementId({
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

    final stateView = _buildStateView(state);
    final selectionConfig = _resolveSelectionConfigForInput(state);
    final hitResult = draw_hit_test.hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: widget.store.context.elementRegistry,
      filterTypeId: widget.currentToolTypeId,
    );
    if (hitResult.isHandleHit) {
      return null;
    }

    final elementId = hitResult.elementId;
    if (elementId == null) {
      return null;
    }
    if (state.domain.selection.selectedIds.contains(elementId)) {
      return null;
    }
    return elementId;
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
    if (element == null || element.data is! ArrowData) {
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
      }
    }
    var isFixed = false;
    final element = stateView.state.domain.document.getElementById(
      context.elementId,
    );
    final effectiveElement =
        element == null ? null : stateView.effectiveElement(element);
    final data = effectiveElement?.data;
    if (data is ArrowData &&
        data.arrowType == ArrowType.elbow &&
        kind == ArrowPointKind.addable) {
      final segmentIndex = index + 1;
      isFixed = data.fixedSegments?.any((segment) => segment.index == segmentIndex) ??
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

  MouseCursor? _resolveArrowHandleCursor({
    required DrawState state,
    required ArrowPointHandle handle,
  }) {
    if (handle.kind != ArrowPointKind.addable) {
      return null;
    }
    final element = state.domain.document.getElementById(handle.elementId);
    if (element == null || element.data is! ArrowData) {
      return null;
    }
    final data = element.data as ArrowData;
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

    final interaction = selectionConfig.interaction;
    final render = selectionConfig.render;
    return selectionConfig.copyWith(
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

    final isSelectionToolActive = widget.currentToolTypeId == null;
    if (!isSelectionToolActive) {
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
    final lockedCursor = _cursorResolver.resolveLockedCursor(
      state.application.interaction,
    );
    if (lockedCursor != null) {
      return lockedCursor;
    }

    if (!_isPointerInside || position == null) {
      return _defaultCursor;
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
      return _defaultCursor;
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
      return _defaultCursor;
    }
    return _cursorResolver.resolveForHitTest(hitResult);
  }

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.0001;

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
      _resetVerticalCaretRun();
    } else if (!_suppressTextControllerChange &&
        controller.text != interaction.draftData.text) {
      _suppressTextControllerChange = true;
      controller.text = interaction.draftData.text;
      _suppressTextControllerChange = false;
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
    final layout = _editingTextLayout;
    if (controller == null || layout == null) {
      return;
    }
    final selection = controller.selection;
    if (!selection.isValid) {
      return;
    }

    final lineMetrics = layout.painter.computeLineMetrics();
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
    final position = layout.painter.getPositionForOffset(offset);
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

  void _handleEvent(DrawEvent event) {
    if (event is HistoryAvailabilityChangedEvent) {
      return;
    }
    if (event is! StateChangeEvent) {
      return;
    }
    final cursor = _resolveCursorForState(
      widget.store.state,
      _lastPointerPosition,
    );
    final nextHover = _lastPointerPosition == null
        ? null
        : _resolveHoverSelectionElementId(
            state: widget.store.state,
            position: _lastPointerPosition!,
          );
    final nextArrowHandle = _lastPointerPosition == null
        ? null
        : _resolveArrowPointHandleForPosition(
            state: widget.store.state,
            position: _lastPointerPosition!,
          );
    if (!mounted) {
      _cursor = cursor;
      _hoveredSelectionElementId = nextHover;
      _hoveredArrowHandle = nextArrowHandle;
      return;
    }
    _updateCursorIfChanged(cursor);
    _hoveredSelectionElementId = nextHover;
    _hoveredArrowHandle = nextArrowHandle;
    setState(() {});
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

  void _updateToolPlugins(ElementTypeId<ElementData>? toolTypeId) {
    final createPlugin = _pluginCoordinator.registry.getPlugin('create');
    if (createPlugin is CreatePlugin) {
      createPlugin.currentToolTypeId = toolTypeId;
    }
    final textPlugin = _pluginCoordinator.registry.getPlugin('text_tool');
    if (textPlugin is TextToolPlugin) {
      textPlugin.currentToolTypeId = toolTypeId;
    }
    final selectPlugin = _pluginCoordinator.registry.getPlugin('select');
    if (selectPlugin is SelectPlugin) {
      selectPlugin.currentToolTypeId = toolTypeId;
    }
  }

  Future<void> _resetInteractionForToolChange() async {
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
