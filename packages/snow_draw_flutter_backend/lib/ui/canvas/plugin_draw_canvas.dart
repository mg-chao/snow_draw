import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' hide HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

import '../../extensions/coordinate_service_offset_extensions.dart';
import '../../extensions/draw_color_extensions.dart';
import '../../render/geometry/arrow_geometry.dart';
import '../../render/text/text_renderer.dart';
import '../../services/text/flutter_text_layout.dart';
import '../../services/text/flutter_text_rendering_cache_invalidation.dart';
import 'cursor_resolver.dart';
import 'filter_shader_manager.dart';
import 'frame_aligned_pointer_move_dispatcher.dart';
import 'grid_shader_painter.dart';
import 'highlight_mask_shader_manager.dart';
import 'rectangle_shader_manager.dart';
import 'render_keys.dart';
import 'scene_canvas_painter.dart';

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
    this.watermarkPreviewListenable,
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
  final ValueListenable<WatermarkConfig?>? watermarkPreviewListenable;

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
      ..add(
        DiagnosticsProperty<ValueListenable<WatermarkConfig?>?>(
          'watermarkPreviewListenable',
          watermarkPreviewListenable,
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
  // Keep store synchronization responsive while reducing high-frequency
  // interaction churn that can compete with text overlay rendering.
  static const _textDraftSyncMinInterval = Duration(milliseconds: 24);
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
  static const _frameRenderPlanBuilder = FrameRenderPlanBuilder();

  VoidCallback? _stateUnsubscribe;
  StreamSubscription<DrawConfig>? _configSubscription;
  final _focusNode = FocusNode();
  late final FocusNode _textFocusNode;
  TextEditingController? _textController;
  String? _editingElementId;
  var _suppressTextControllerChange = false;
  var _initialSelectionApplied = false;
  var _textFocusScheduled = false;
  FlutterTextLayoutMetrics? _editingTextLayout;
  _EditingLayoutIdentity? _editingTextLayoutKey;
  FlutterPainterTextLayoutMetrics? _editingPainterLayout;
  _EditingLayoutIdentity? _editingPainterLayoutKey;
  TextSelection? _lastVerticalSelection;
  double? _verticalCaretX;
  final _cursorResolver = const CursorResolver();
  final _cursorNotifier = ValueNotifier<MouseCursor>(_defaultCursor);
  final _textOverlayNotifier = ValueNotifier<_TextEditingOverlaySnapshot?>(
    null,
  );
  late final ValueNotifier<_CanvasSnapshot> _canvasSnapshotNotifier;
  late final FrameAlignedEventDispatcher<_PendingTextDraftSync>
  _textDraftDispatcher;
  _PendingTextDraftSync? _pendingTextDraftSync;
  Timer? _textDraftSyncTimer;
  DateTime? _lastTextDraftSyncAt;

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
  final _eraserHitTesterByType =
      <ElementTypeId<ElementData>, ElementHitTester?>{};
  final _eraserCursorPositionNotifier = ValueNotifier<DrawPoint?>(null);
  int? _middlePanPointerId;
  Offset? _lastMiddlePanPosition;

  CoordinateService? _coordinateService;
  late PluginInputCoordinator _pluginCoordinator;
  late DrawStateViewBuilder _stateViewBuilder;
  late final FrameAlignedPointerMoveDispatcher _pointerMoveDispatcher;
  late final FrameAlignedEventDispatcher<_HoverFrameEvent> _hoverMoveDispatcher;
  late final FrameAlignedEventDispatcher<_EraserMoveEvent>
  _eraserMoveDispatcher;
  late final EraserStrokeProcessor _eraserStrokeProcessor;
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
      _coords.screenOffsetToWorld(localPosition);

  Future<void> _recreatePluginCoordinator() async {
    final inputLog = widget.store.context.log.input;

    final pluginContext = PluginContext(
      stateProvider: () => widget.store.state,
      contextProvider: () => widget.store.context,
      selectionConfigProvider: () =>
          _resolveSelectionConfigForInput(widget.store.state),
      dispatcher: widget.store.dispatch,
    );

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

    final standardPlugins = <InputPlugin>[
      EditPlugin(),
      TextToolPlugin(
        currentToolTypeId: widget.currentToolTypeId,
        isSelectionToolActive: widget.isSelectionToolActive,
      ),
      CreatePlugin(currentToolTypeId: widget.currentToolTypeId),
      SelectPlugin(
        currentToolTypeId: widget.currentToolTypeId,
        isSelectionToolActive: widget.isSelectionToolActive,
      ),
      BoxSelectPlugin(),
    ];
    final plugins = <InputPlugin>[...standardPlugins, ...?widget.customPlugins];
    await _pluginCoordinator.registry.registerAll(plugins);

    _updateToolPlugins(
      toolTypeId: widget.currentToolTypeId,
      isSelectionToolActive: widget.isSelectionToolActive,
    );

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
    ensureFlutterTextRenderingCacheInvalidatorInstalled();
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
    _textDraftDispatcher = FrameAlignedEventDispatcher<_PendingTextDraftSync>(
      dispatchEvent: _dispatchPendingTextDraftSync,
      shouldCoalesce: () => true,
    );
    _eraserMoveDispatcher = FrameAlignedEventDispatcher<_EraserMoveEvent>(
      dispatchEvent: _dispatchEraserMove,
      shouldCoalesce: () => _eraserPointerIds.length <= 1,
    );
    _eraserStrokeProcessor = EraserStrokeProcessor(
      hitTesterResolver: _resolveEraserHitTester,
    );
    unawaited(_recreatePluginCoordinator());
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: widget.store.context.editOperations,
    );
    _syncTextEditingOverlayState(initialState);
    widget.watermarkPreviewListenable?.addListener(
      _handleWatermarkPreviewChange,
    );
    final initialCanvasSnapshot = _createInitialCanvasSnapshot(initialState);
    _canvasSnapshotNotifier = ValueNotifier<_CanvasSnapshot>(
      initialCanvasSnapshot,
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
        _pendingTextDraftSync = null;
        _cancelPendingTextDraftSyncDispatch();
        _lastTextDraftSyncAt = null;
        _textDraftDispatcher.reset();
        _cachedInputSelectionConfigSource = null;
        _cachedInputSelectionConfig = null;
        _cachedInputSelectionScale = null;
        _syncTextEditingOverlayState(widget.store.state);
        final initialCanvasSnapshot = _createInitialCanvasSnapshot(
          widget.store.state,
        );
        _canvasSnapshotNotifier.value = initialCanvasSnapshot;

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
    if (oldWidget.watermarkPreviewListenable !=
        widget.watermarkPreviewListenable) {
      oldWidget.watermarkPreviewListenable?.removeListener(
        _handleWatermarkPreviewChange,
      );
      widget.watermarkPreviewListenable?.addListener(
        _handleWatermarkPreviewChange,
      );
    }

    _updateCursorIfChanged(
      _resolveCursorForState(widget.store.state, _lastPointerPosition),
    );
    _syncTextEditingOverlayState(widget.store.state);
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
    widget.watermarkPreviewListenable?.removeListener(
      _handleWatermarkPreviewChange,
    );
    _focusNode.dispose();
    _disposeTextEditor();
    _textFocusNode.dispose();
    _cursorNotifier.dispose();
    _textOverlayNotifier.dispose();
    _canvasSnapshotNotifier.dispose();
    _eraserCursorPositionNotifier.dispose();
    unawaited(_pointerMoveDispatcher.dispose());
    unawaited(_hoverMoveDispatcher.dispose());
    unawaited(_textDraftDispatcher.dispose());
    unawaited(_eraserMoveDispatcher.dispose());
    unawaited(_pluginCoordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleFactor = _effectiveScaleFactor();
    final locale = Localizations.maybeLocaleOf(context);
    _syncCanvasSnapshotForBuild(locale: locale);
    final textOverlay = _buildTextEditorOverlay(
      scaleFactor: scaleFactor,
      locale: locale,
    );
    final eraserCursorOverlay = _buildEraserCursorOverlay();

    final paintStack = Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      onPointerSignal: _handlePointerSignal,
      child: Stack(
        children: [
          RepaintBoundary(
            child: ValueListenableBuilder<_CanvasSnapshot>(
              valueListenable: _canvasSnapshotNotifier,
              builder: (context, snapshot, _) => CustomPaint(
                painter: SceneCanvasPainter(
                  renderKey: snapshot.renderKey,
                  stateView: snapshot.stateView,
                ),
                size: widget.size,
              ),
            ),
          ),
          textOverlay,
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

  /// Extract preview elements for the unified canvas.
  ///
  /// Creating interactions are excluded from this preview map.
  Map<String, ElementState> _previewElementsForCanvas(DrawStateView view) {
    final interaction = view.state.application.interaction;
    if (interaction is CreatingState) {
      return const <String, ElementState>{};
    }

    if (interaction is TextEditingState) {
      if (interaction.isNew) {
        return const <String, ElementState>{};
      }

      final hiddenPreview = _buildHiddenTextEditingPreview(view);
      if (hiddenPreview == null) {
        return const <String, ElementState>{};
      }
      return {hiddenPreview.id: hiddenPreview};
    }

    return view.previewElementsById;
  }

  ElementState? _buildHiddenTextEditingPreview(DrawStateView view) {
    final interaction = view.state.application.interaction;
    if (interaction is! TextEditingState) {
      return null;
    }
    final previewElement = view.previewElementsById[interaction.elementId];
    final documentElement = view.state.domain.document.getElementById(
      interaction.elementId,
    );
    final sourceElement = previewElement ?? documentElement;
    if (sourceElement == null || sourceElement.data is! TextData) {
      return null;
    }
    if (_doubleEquals(sourceElement.opacity, 0)) {
      return sourceElement;
    }
    return sourceElement.copyWith(opacity: 0);
  }

  Map<String, ElementState> _resolveEraserPreviewElements(
    DrawStateView stateView,
  ) {
    final pending = _pendingErasePreviewElementsById;
    if (pending.isEmpty) {
      return stateView.previewElementsById;
    }
    if (stateView.previewElementsById.isEmpty) {
      return pending;
    }
    return Map<String, ElementState>.unmodifiable({
      ...stateView.previewElementsById,
      ...pending,
    });
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

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
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
    unawaited(_handlePointerDownAsync(event));
  }

  Future<void> _handlePointerDownAsync(PointerDownEvent event) async {
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
        _eraserStrokeProcessor.reset();
      }
      _eraserStrokeProcessor.clearPointer(event.pointer);
      final hadPendingPreview = _pendingErasePreviewElementsById.isNotEmpty;
      final previewChanged = _markElementsForErase(
        pointerId: event.pointer,
        position: position,
      );
      if (previewChanged) {
        _handleEraserPreviewMutation(hadPendingPreview: hadPendingPreview);
      }
      return;
    }
    if (widget.store.state.application.interaction is TextEditingState) {
      await _flushPendingTextDraftSync();
    }
    await _pluginCoordinator.handleEvent(
      PointerDownInputEvent(position: position, modifiers: _currentModifiers),
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
      PointerMoveInputEvent(position: position, modifiers: _currentModifiers),
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
    final hoverChanged = _updateCursorAndHoverForPosition(event.position);
    if (hoverChanged) {
      _refreshCanvasSnapshot(widget.store.state);
    }
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
    final hadPendingPreview = _pendingErasePreviewElementsById.isNotEmpty;
    final previewChanged = _markElementsForErase(
      pointerId: event.pointerId,
      position: event.position,
    );
    if (previewChanged) {
      _handleEraserPreviewMutation(hadPendingPreview: hadPendingPreview);
    }
  }

  Future<void> _finishEraserStroke() async {
    await _eraserMoveDispatcher.flush();
    _eraserStrokeProcessor.reset();
    await _commitPendingErase();
  }

  bool _shouldFrameCoalescePointerMove() {
    final state = widget.store.state;
    final interaction = state.application.interaction;
    return PointerMoveDispatchPolicy.shouldCoalesce(
      interaction: interaction,
      currentToolTypeId: widget.currentToolTypeId,
      isShiftPressed: _isShiftPressed,
      isLowLatencySerialInteraction:
          SerialNumberInteractionClassifier.isLowLatencySerialInteraction(
            interaction: interaction,
            document: state.domain.document,
          ),
    );
  }

  bool _shouldBatchFreeDrawMoves() {
    final interaction = widget.store.state.application.interaction;
    return PointerMoveDispatchPolicy.shouldBatchFreeDrawSamples(
      interaction: interaction,
      currentToolTypeId: widget.currentToolTypeId,
      isShiftPressed: _isShiftPressed,
    );
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
    final hoverChanged = _updateCursorAndHoverForPosition(position);
    if (hoverChanged) {
      _refreshCanvasSnapshot(widget.store.state);
    }
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final position = _recordPointerPosition(event.localPosition);
    _queueHoverUpdate(
      position: position,
      dispatchPluginHover: !widget.isEraserToolActive,
    );
  }

  void _handlePointerExit(PointerExitEvent _) {
    _isPointerInside = false;
    _lastPointerPosition = null;
    _eraserCursorPositionNotifier.value = null;
    _hoverMoveDispatcher.reset();
    final hoverChanged = _applyHoverState(
      selectionId: null,
      bindingId: null,
      arrowHandle: null,
    );
    final nextCursor = _resolveCursorForState(widget.store.state, null);
    _updateCursorIfChanged(nextCursor);
    if (hoverChanged) {
      _refreshCanvasSnapshot(widget.store.state);
    }
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
  }) => _eraserStrokeProcessor.markElementsForErase(
    pointerId: pointerId,
    position: position,
    stateView: _buildStateView(widget.store.state),
    tolerance: _eraserCursorRadius / _effectiveScaleFactor(),
    isQueuedForPreview: _pendingErasePreviewElementsById.containsKey,
    queuePreview: _queueElementForErasePreview,
  );

  void _handleEraserPreviewMutation({required bool hadPendingPreview}) {
    final hasPendingPreview = _pendingErasePreviewElementsById.isNotEmpty;
    if (!mounted || (!hasPendingPreview && !hadPendingPreview)) {
      return;
    }
    _refreshCanvasSnapshot(widget.store.state);
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

  Future<void> _commitPendingErase() async {
    if (_pendingErasePreviewElementsById.isEmpty) {
      return;
    }
    final ids = _pendingErasePreviewElementsById.keys.toList(growable: false);
    _pendingErasePreviewElementsById.clear();
    _handleEraserPreviewMutation(hadPendingPreview: true);
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
    _eraserStrokeProcessor.reset();
    if (_eraserPointerIds.isNotEmpty) {
      _activePointerIds.removeAll(_eraserPointerIds);
      _eraserPointerIds.clear();
    }
    final hadPendingPreview = _pendingErasePreviewElementsById.isNotEmpty;
    _pendingErasePreviewElementsById.clear();
    if (!hadPendingPreview) {
      return;
    }
    _handleEraserPreviewMutation(hadPendingPreview: true);
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
    _refreshCanvasSnapshot(widget.store.state);
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
    final arrowAverage = resolveAverageSelectedArrowStrokeWidth(state);
    final lineAverage = resolveAverageSelectedLineStrokeWidth(state);
    final freeDrawAverage = resolveAverageSelectedFreeDrawStrokeWidth(state);
    final rectangleAverage = resolveAverageSelectedRectangleStrokeWidth(state);
    final base =
        arrowAverage ??
        lineAverage ??
        freeDrawAverage ??
        rectangleAverage ??
        config.arrowStyle.strokeWidth;

    // Find next stepped value
    final next = resolveNextSteppedValue(
      base,
      _strokeWidthSteps,
      decrease: delta > 0, // scrolling up decreases value
    );

    if (_doubleEquals(next, base)) {
      return;
    }

    void updateSelectedStrokeWidth(List<String> elementIds) {
      if (elementIds.isEmpty) {
        return;
      }
      unawaited(
        widget.store.dispatch(
          UpdateElementsStyle(elementIds: elementIds, strokeWidth: next),
        ),
      );
    }

    updateSelectedStrokeWidth(_resolveArrowSelectionIds(state));
    updateSelectedStrokeWidth(_resolveRectangleSelectionIds(state));
    updateSelectedStrokeWidth(_resolveLineSelectionIds(state));
    updateSelectedStrokeWidth(_resolveFreeDrawSelectionIds(state));

    var nextConfig = config;
    var configChanged = false;
    if (!_doubleEquals(next, nextConfig.arrowStyle.strokeWidth)) {
      nextConfig = nextConfig.copyWith(
        arrowStyle: nextConfig.arrowStyle.copyWith(strokeWidth: next),
      );
      configChanged = true;
    }
    if (!_doubleEquals(next, nextConfig.rectangleStyle.strokeWidth)) {
      nextConfig = nextConfig.copyWith(
        rectangleStyle: nextConfig.rectangleStyle.copyWith(strokeWidth: next),
      );
      configChanged = true;
    }
    if (!_doubleEquals(next, nextConfig.lineStyle.strokeWidth)) {
      nextConfig = nextConfig.copyWith(
        lineStyle: nextConfig.lineStyle.copyWith(strokeWidth: next),
      );
      configChanged = true;
    }
    if (!_doubleEquals(next, nextConfig.freeDrawStyle.strokeWidth)) {
      nextConfig = nextConfig.copyWith(
        freeDrawStyle: nextConfig.freeDrawStyle.copyWith(strokeWidth: next),
      );
      configChanged = true;
    }
    if (configChanged) {
      unawaited(widget.store.dispatch(UpdateConfig(nextConfig)));
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
        resolveAverageSelectedFontSize(state) ??
        (toolTypeId == SerialNumberData.typeIdToken
            ? config.serialNumberStyle.fontSize
            : config.textStyle.fontSize);

    // Find next stepped value
    final next = resolveNextSteppedValue(
      base,
      _fontSizeSteps,
      decrease: delta > 0, // scrolling up decreases value
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

    final serialNumberIds = _resolveSerialNumberSelectionIds(state);
    final updateSerialNumberStyle =
        serialNumberIds.isNotEmpty ||
        toolTypeId == SerialNumberData.typeIdToken;

    var nextConfig = config;
    var configChanged = false;
    if (!_doubleEquals(next, nextConfig.textStyle.fontSize)) {
      nextConfig = nextConfig.copyWith(
        textStyle: nextConfig.textStyle.copyWith(fontSize: next),
      );
      configChanged = true;
    }
    if (updateSerialNumberStyle &&
        !_doubleEquals(next, nextConfig.serialNumberStyle.fontSize)) {
      nextConfig = nextConfig.copyWith(
        serialNumberStyle: nextConfig.serialNumberStyle.copyWith(
          fontSize: next,
        ),
      );
      configChanged = true;
    }
    if (configChanged) {
      unawaited(widget.store.dispatch(UpdateConfig(nextConfig)));
    }
  }

  double? _resolveEditingFontSize(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is TextEditingState) {
      return interaction.draftData.fontSize;
    }
    return null;
  }

  List<String> _resolveSelectionIds(
    DrawState state,
    bool Function(ElementData data) matcher,
  ) {
    final selectedIds = state.domain.selection.selectedIds;
    if (selectedIds.isEmpty) {
      return const [];
    }

    final document = state.domain.document;
    final ids = <String>[];
    for (final id in selectedIds) {
      final data = document.getElementById(id)?.data;
      if (data != null && matcher(data)) {
        ids.add(id);
      }
    }
    return ids;
  }

  List<String> _resolveRectangleSelectionIds(DrawState state) =>
      _resolveSelectionIds(state, (data) => data is RectangleData);

  List<String> _resolveArrowSelectionIds(DrawState state) =>
      _resolveSelectionIds(state, (data) => data is ArrowData);

  List<String> _resolveLineSelectionIds(DrawState state) =>
      _resolveSelectionIds(state, (data) => data is LineData);

  List<String> _resolveFreeDrawSelectionIds(DrawState state) =>
      _resolveSelectionIds(state, (data) => data is FreeDrawData);

  List<String> _resolveTextSelectionIds(DrawState state) {
    final ids = _resolveSelectionIds(
      state,
      (data) => data is TextData || data is SerialNumberData,
    );
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState ||
        ids.contains(interaction.elementId)) {
      return ids;
    }
    return [...ids, interaction.elementId];
  }

  List<String> _resolveSerialNumberSelectionIds(DrawState state) =>
      _resolveSelectionIds(state, (data) => data is SerialNumberData);

  /// Computes cursor and hover state in a single pass, sharing the
  /// hit test result and arrow-handle lookup between both paths.
  bool _updateCursorAndHoverForPosition(DrawPoint position) {
    final state = widget.store.state;
    final interaction = state.application.interaction;

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
    final hitResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: widget.store.context.elementRegistry,
      filterTypeId: widget.currentToolTypeId,
    );

    MouseCursor nextCursor;
    if (_shouldForceDefaultCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
    )) {
      nextCursor = _idleCursorForCurrentTool;
    } else if (_shouldShowTextCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
    )) {
      nextCursor = SystemMouseCursors.text;
    } else if (!hitResult.isHit) {
      nextCursor = _idleCursorForCurrentTool;
    } else {
      nextCursor = _cursorResolver.resolveForHitTest(hitResult);
    }
    _updateCursorIfChanged(nextCursor);

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
    _hoveredSelectionElementId = selectionId;
    _hoveredBindingElementId = bindingId;
    _hoveredArrowHandle = arrowHandle;
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
    if (!shouldPreviewArrowBinding(
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
    final targets = resolveArrowBindingTargets(
      state: state,
      position: position,
      distance: searchDistance,
    );
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
    final snapConfig = widget.store.config.snap;
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
      elements: stateView.elements,
      zoom: state.application.view.camera.zoom,
      isBindingEnabled: snapConfig.enableArrowBinding,
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
    final points = FlutterArrowGeometry.resolveWorldPoints(
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

    final scaled = scaleSelectionConfigForInput(
      selectionConfig: selectionConfig,
      scaleFactor: effectiveScale,
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
    required HitTestResult hitResult,
  }) {
    if (hitResult.isHandleHit) {
      return false;
    }

    final interaction = _resolveVisibleTextEditingInteraction(state);
    if (interaction != null) {
      if (_isInsideRect(interaction.rect, interaction.rotation, position)) {
        return true;
      }

      final selectionHit = _isSelectionHit(hitResult);
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
    required HitTestResult hitResult,
  }) {
    final interaction = _resolveVisibleTextEditingInteraction(state);
    if (interaction == null) {
      return false;
    }

    if (_isInsideRect(interaction.rect, interaction.rotation, position)) {
      return false;
    }

    final selectionHit = _isSelectionHit(hitResult);
    if (selectionHit) {
      return false;
    }

    final isTextToolActive = widget.currentToolTypeId == TextData.typeIdToken;
    if (!isTextToolActive) {
      return true;
    }

    return !_isInsideAnyTextElement(stateView, position);
  }

  bool _isSelectionHit(HitTestResult hitResult) =>
      hitResult.isHandleHit || hitResult.isInSelectionPadding;

  bool _shouldDeferToSelectionBox({
    required DrawStateView stateView,
    required DrawPoint position,
    required HitTestResult hitResult,
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

    if (!_isSelectionHit(hitResult)) {
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
    final hitResult = hitTest.test(
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
    )) {
      return _idleCursorForCurrentTool;
    }
    if (_shouldShowTextCursor(
      state: state,
      position: position,
      stateView: stateView,
      hitResult: hitResult,
    )) {
      return SystemMouseCursors.text;
    }
    if (!hitResult.isHit) {
      return _idleCursorForCurrentTool;
    }
    return _cursorResolver.resolveForHitTest(hitResult);
  }

  void _handleWatermarkPreviewChange() {
    _refreshCanvasSnapshot(widget.store.state);
  }

  WatermarkConfig _resolveEffectiveWatermarkConfig(DrawState state) =>
      widget.watermarkPreviewListenable?.value ??
      state.domain.document.globalElements.watermark;

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.0001;

  bool get _isElementInteractionDisabledForCurrentTool =>
      widget.isEraserToolActive ||
      (widget.currentToolTypeId == null && !widget.isSelectionToolActive);

  MouseCursor get _idleCursorForCurrentTool => widget.isEraserToolActive
      ? SystemMouseCursors.none
      : _isElementInteractionDisabledForCurrentTool
      ? SystemMouseCursors.basic
      : _defaultCursor;

  DrawStateView _buildStateView(DrawState state) =>
      _stateViewBuilder.build(state);

  _CanvasRenderInputs _resolveCanvasRenderInputs(DrawStateView stateView) {
    final promoteEraserPreviewToRenderInputs =
        widget.isEraserToolActive &&
        _pendingErasePreviewElementsById.isNotEmpty;
    final previewElements = promoteEraserPreviewToRenderInputs
        ? _resolveEraserPreviewElements(stateView)
        : _previewElementsForCanvas(stateView);

    final creatingSnapshot = _extractCreatingSnapshot(stateView);
    final globalElements = stateView.globalElements;
    final highlightMask = globalElements.highlightMask;
    final watermark = _resolveEffectiveWatermarkConfig(stateView.state);

    return _CanvasRenderInputs(
      previewElements: previewElements,
      creatingSnapshot: creatingSnapshot,
      highlightMaskConfig: highlightMask,
      watermarkConfig: watermark,
      textRenderingCacheRevision: textRenderingCacheRevisionListenable.value,
    );
  }

  SceneCanvasRenderKey _buildCanvasRenderKey({
    required DrawStateView stateView,
    required SelectionConfig selectionConfig,
    required double scaleFactor,
    required _CanvasRenderInputs inputs,
    required Locale? locale,
  }) => _createCanvasRenderKey(
    stateView: stateView,
    selectionConfig: selectionConfig,
    scaleFactor: scaleFactor,
    creatingElement: inputs.creatingSnapshot,
    textRenderingCacheRevision: inputs.textRenderingCacheRevision,
    previewElementsById: inputs.previewElements,
    highlightMaskConfig: inputs.highlightMaskConfig,
    watermarkConfig: inputs.watermarkConfig,
    locale: locale,
  );

  SceneCanvasRenderKey _createCanvasRenderKey({
    required DrawStateView stateView,
    required SelectionConfig selectionConfig,
    required double scaleFactor,
    required CreatingElementSnapshot? creatingElement,
    required int textRenderingCacheRevision,
    required Map<String, ElementState> previewElementsById,
    required HighlightMaskConfig highlightMaskConfig,
    required WatermarkConfig watermarkConfig,
    required Locale? locale,
  }) {
    final boxSelectionBounds = _extractBoxSelectionBounds(stateView);
    final activeArrowHandle = _resolveActiveArrowHandle(stateView);
    final arrowDeleteIndicatorVisible = _isArrowDeleteIndicatorVisible(
      stateView,
    );
    final hoverSelectionConfig = _resolveHoverSelectionConfig();
    final boxSelectionConfig = widget.store.config.boxSelection;
    final snapConfig = widget.store.config.snap;
    final canvasConfig = widget.store.config.canvas;
    final gridConfig = widget.store.config.grid;
    final elementRegistry = widget.store.context.elementRegistry;
    final framePlan = _frameRenderPlanBuilder.build(
      view: stateView,
      scaleFactor: scaleFactor,
      transientState: FrameRenderTransientState(
        hoveredElementId: _hoveredSelectionElementId,
        hoveredBindingElementId: _hoveredBindingElementId,
        hoveredArrowHandle: _hoveredArrowHandle,
        activeArrowHandle: activeArrowHandle,
        arrowDeleteIndicatorVisible: arrowDeleteIndicatorVisible,
        selectionConfig: selectionConfig,
        hoverSelectionConfig: hoverSelectionConfig,
        boxSelectionConfig: boxSelectionConfig,
        snapConfig: snapConfig,
        canvasConfig: canvasConfig,
        gridConfig: gridConfig,
        highlightMaskConfig: highlightMaskConfig,
        watermarkConfig: watermarkConfig,
        boxSelectionBounds: boxSelectionBounds,
        previewElementsById: previewElementsById,
      ),
    );

    return SceneCanvasRenderKey(
      documentElementsVersion: stateView.state.domain.document.elementsVersion,
      creatingElement: creatingElement,
      textRenderingCacheRevision: textRenderingCacheRevision,
      previewElementsById: previewElementsById,
      elementRegistry: elementRegistry,
      textMetricsService: widget.store.context.textMetricsService,
      performanceMonitoringEnabled: widget.enablePerformanceMonitoring,
      locale: locale,
      framePlan: framePlan,
    );
  }

  _CanvasSnapshot _createInitialCanvasSnapshot(DrawState state) {
    final stateView = _buildStateView(state);
    final inputs = _resolveCanvasRenderInputs(stateView);
    final renderKey = _buildCanvasRenderKey(
      stateView: stateView,
      selectionConfig: _resolveSelectionConfig(state),
      scaleFactor: _effectiveScaleFactor(),
      inputs: inputs,
      locale: null,
    );
    return _CanvasSnapshot(stateView: stateView, renderKey: renderKey);
  }

  void _setCanvasSnapshot({
    required DrawStateView stateView,
    required SceneCanvasRenderKey renderKey,
  }) {
    final nextSnapshot = _CanvasSnapshot(
      stateView: stateView,
      renderKey: renderKey,
    );
    _canvasSnapshotNotifier.value = nextSnapshot;
  }

  Locale? _resolveCanvasLocale() =>
      Localizations.maybeLocaleOf(context) ??
      _canvasSnapshotNotifier.value.renderKey.locale;

  void _syncCanvasSnapshotForBuild({required Locale? locale}) {
    final currentRenderKey = _canvasSnapshotNotifier.value.renderKey;
    final currentScale = currentRenderKey.framePlan.scaleFactor;
    final requestedScale = _effectiveScaleFactor();
    final targetScale = requestedScale.isFinite && requestedScale > 0
        ? requestedScale
        : 1.0;
    final scaleChanged = !_doubleEquals(currentScale, targetScale);
    final localeChanged = currentRenderKey.locale != locale;
    final monitoringChanged =
        currentRenderKey.performanceMonitoringEnabled !=
        widget.enablePerformanceMonitoring;
    if (!scaleChanged && !localeChanged && !monitoringChanged) {
      return;
    }
    _refreshCanvasSnapshot(widget.store.state, localeOverride: locale);
  }

  void _refreshCanvasSnapshot(DrawState state, {Locale? localeOverride}) {
    if (!mounted) {
      return;
    }

    final stateView = _buildStateView(state);
    final inputs = _resolveCanvasRenderInputs(stateView);
    final scaleFactor = _effectiveScaleFactor();
    final locale = localeOverride ?? _resolveCanvasLocale();
    final canvasRenderKey = _buildCanvasRenderKey(
      stateView: stateView,
      selectionConfig: _resolveSelectionConfig(state),
      scaleFactor: scaleFactor,
      inputs: inputs,
      locale: locale,
    );
    _setCanvasSnapshot(stateView: stateView, renderKey: canvasRenderKey);
  }

  Widget _buildTextEditorOverlay({
    required double scaleFactor,
    Locale? locale,
  }) => ValueListenableBuilder<_TextEditingOverlaySnapshot?>(
    valueListenable: _textOverlayNotifier,
    builder: (context, snapshot, _) {
      if (snapshot == null) {
        _clearEditingTextLayoutCache();
        _clearEditingPainterLayoutCache();
        return const SizedBox.shrink();
      }

      final controller = _textController;
      if (controller == null) {
        return const SizedBox.shrink();
      }

      final rect = snapshot.rect;
      final topLeft = _coords.worldToScreen(
        DrawPoint(x: rect.minX, y: rect.minY),
      );
      final layoutWidth = rect.width;
      final height = rect.height;
      if (layoutWidth <= 0 || height <= 0) {
        _clearEditingTextLayoutCache();
        _clearEditingPainterLayoutCache();
        return const SizedBox.shrink();
      }

      final text = controller.text;
      final data = text == snapshot.data.text
          ? snapshot.data
          : snapshot.data.copyWith(text: text);
      final opacity = snapshot.opacity;
      final textOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
      final textColor = data.color
          .withValues(alpha: textOpacity)
          .toFlutterColor();
      final textStyle = buildTextStyle(
        data: data,
        colorOverride: textColor,
        locale: locale,
      );

      final layout = _resolveEditingTextLayout(
        data: data,
        layoutWidth: layoutWidth,
        locale: locale,
      );
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
        interaction: snapshot.toInteractionState(),
        rect: rect,
        layout: layout,
        verticalOffset: verticalOffset,
      );

      // RenderEditable subtracts a caret margin from maxWidth when laying out.
      final fieldWidth = layoutWidth + textCaretMargin;
      final shouldPaintTextDecorations = _shouldPaintTextDecorations(
        data: data,
        opacity: opacity,
      );
      Widget textField = TextField(
        controller: controller,
        focusNode: _textFocusNode,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        maxLines: null,
        enableSuggestions: false,
        autocorrect: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
        style: textStyle,
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
            angle: snapshot.rotation,
            child: SizedBox(
              width: layoutWidth,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (shouldPaintTextDecorations)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _EditingTextOverlayPainter(
                              elementId: snapshot.elementId,
                              data: data.copyWith(
                                color: data.color.withValues(alpha: 0),
                              ),
                              opacity: opacity,
                              locale: locale,
                              layout: layout,
                              cacheRevision:
                                  textRenderingCacheRevisionListenable.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: verticalOffset,
                    width: fieldWidth,
                    height: textHeight,
                    child: RepaintBoundary(
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
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  void _syncTextEditor(TextEditingState interaction) {
    final controller = _textController;
    if (controller == null || _editingElementId != interaction.elementId) {
      _disposeTextEditor();
      _textController = TextEditingController(text: interaction.draftData.text)
        ..addListener(_handleTextControllerChanged);
      _editingElementId = interaction.elementId;
      _initialSelectionApplied = false;
      _clearEditingTextLayoutCache();
      _clearEditingPainterLayoutCache();
      _resetVerticalCaretRun();
      _pendingTextDraftSync = null;
      _cancelPendingTextDraftSyncDispatch();
      _lastTextDraftSyncAt = null;
    } else if (_pendingTextDraftSync != null &&
        _pendingTextDraftSync!.elementId == interaction.elementId &&
        _isSameTextValue(
          interaction.draftData.text,
          _pendingTextDraftSync!.text,
        )) {
      _pendingTextDraftSync = null;
      _cancelPendingTextDraftSyncDispatch();
    } else if (!_suppressTextControllerChange &&
        controller.text != interaction.draftData.text &&
        (_pendingTextDraftSync == null ||
            _pendingTextDraftSync!.elementId != interaction.elementId ||
            controller.text != _pendingTextDraftSync!.text)) {
      _suppressTextControllerChange = true;
      controller.text = interaction.draftData.text;
      _suppressTextControllerChange = false;
      _clearEditingTextLayoutCache();
      _clearEditingPainterLayoutCache();
    }

    _scheduleTextFocus();
  }

  void _disposeTextEditor() {
    _pendingTextDraftSync = null;
    _cancelPendingTextDraftSyncDispatch();
    _lastTextDraftSyncAt = null;
    _textDraftDispatcher.reset();
    final controller = _textController;
    if (controller != null) {
      controller
        ..removeListener(_handleTextControllerChanged)
        ..dispose();
      _textController = null;
    }
    _editingElementId = null;
    _initialSelectionApplied = false;
    _clearEditingTextLayoutCache();
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

  void _syncTextEditingOverlayState(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      if (_textController != null || _editingElementId != null) {
        _disposeTextEditor();
      }
      if (_textOverlayNotifier.value != null) {
        _textOverlayNotifier.value = null;
      }
      return;
    }

    _syncTextEditor(interaction);
    var nextSnapshot = _TextEditingOverlaySnapshot.fromInteraction(interaction);
    var pending = _pendingTextDraftSync;
    if (pending != null) {
      if (pending.elementId != interaction.elementId) {
        _pendingTextDraftSync = null;
        _cancelPendingTextDraftSyncDispatch();
        pending = null;
      } else if (_isSameTextValue(interaction.draftData.text, pending.text)) {
        _pendingTextDraftSync = null;
        _cancelPendingTextDraftSyncDispatch();
        pending = null;
      } else {
        pending = _resolvePendingTextDraftSyncForInteraction(
          interaction: interaction,
          pending: pending,
        );
        if (_pendingTextDraftSync != pending) {
          _pendingTextDraftSync = pending;
          _schedulePendingTextDraftSyncDispatch();
        }
        final mergedPending = pending;
        nextSnapshot = nextSnapshot.copyWith(
          data: nextSnapshot.data.copyWith(text: mergedPending.text),
          rect: mergedPending.previewRect,
        );
      }
    }
    _setTextOverlaySnapshot(nextSnapshot);
  }

  void _setTextOverlaySnapshot(_TextEditingOverlaySnapshot nextSnapshot) {
    final current = _textOverlayNotifier.value;
    if (_isSameTextOverlaySnapshot(current, nextSnapshot)) {
      return;
    }
    _textOverlayNotifier.value = nextSnapshot;
  }

  bool _isSameTextOverlaySnapshot(
    _TextEditingOverlaySnapshot? current,
    _TextEditingOverlaySnapshot next,
  ) {
    if (current == null) {
      return false;
    }
    if (identical(current, next)) {
      return true;
    }
    return current.elementId == next.elementId &&
        identical(current.data, next.data) &&
        current.rect == next.rect &&
        current.isNew == next.isNew &&
        current.rotation == next.rotation &&
        current.opacity == next.opacity &&
        current.initialCursorPosition == next.initialCursorPosition;
  }

  bool _isSameTextValue(String left, String right) =>
      identical(left, right) || left == right;

  FlutterTextLayoutMetrics _resolveEditingTextLayout({
    required TextData data,
    required double layoutWidth,
    required Locale? locale,
  }) {
    final nextKey = _resolveEditingLayoutIdentity(
      data: data,
      layoutWidth: layoutWidth,
      locale: locale,
    );
    final cachedLayout = _editingTextLayout;
    if (cachedLayout != null && _editingTextLayoutKey == nextKey) {
      return cachedLayout;
    }
    final layout = layoutText(
      data: data,
      maxWidth: layoutWidth,
      minWidth: layoutWidth,
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );
    _editingTextLayout = layout;
    _editingTextLayoutKey = nextKey;
    return layout;
  }

  _EditingLayoutIdentity _resolveEditingLayoutIdentity({
    required TextData data,
    required double layoutWidth,
    required Locale? locale,
  }) => _EditingLayoutIdentity(
    textToken: data.text,
    fontSize: data.fontSize,
    fontFamily: data.fontFamily,
    horizontalAlign: data.horizontalAlign,
    layoutWidth: _quantizeEditingLayoutWidth(layoutWidth),
    localeTag: locale?.toLanguageTag(),
  );

  void _clearEditingTextLayoutCache() {
    _editingTextLayout = null;
    _editingTextLayoutKey = null;
  }

  void _invalidateEditingPainterLayoutIfNeeded({
    required TextData data,
    required double layoutWidth,
    required Locale? locale,
  }) {
    final nextKey = _resolveEditingLayoutIdentity(
      data: data,
      layoutWidth: layoutWidth,
      locale: locale,
    );
    if (_editingPainterLayoutKey == nextKey) {
      return;
    }
    _editingPainterLayoutKey = nextKey;
    _editingPainterLayout = null;
  }

  TextEditingState? _resolveVisibleTextEditingInteraction(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! TextEditingState) {
      return null;
    }
    final overlay = _textOverlayNotifier.value;
    if (overlay == null || overlay.elementId != interaction.elementId) {
      return interaction;
    }
    return overlay.toInteractionState();
  }

  FlutterPainterTextLayoutMetrics? _resolveEditingPainterLayout() {
    final interaction = _resolveVisibleTextEditingInteraction(
      widget.store.state,
    );
    if (interaction == null) {
      return null;
    }
    final layoutWidth = interaction.rect.width;
    if (layoutWidth <= 0) {
      return null;
    }
    final locale = Localizations.maybeLocaleOf(context);
    final nextKey = _resolveEditingLayoutIdentity(
      data: interaction.draftData,
      layoutWidth: layoutWidth,
      locale: locale,
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
    final interaction = _resolveVisibleTextEditingInteraction(
      widget.store.state,
    );
    if (interaction == null) {
      return;
    }
    final nextText = controller.text;
    if (nextText == interaction.draftData.text) {
      return;
    }
    final locale = Localizations.maybeLocaleOf(context);
    final geometry = _resolveTextEditGeometryForDraft(
      interaction: interaction,
      text: nextText,
      locale: locale,
    );
    _editingTextLayout = geometry.layout;
    _editingTextLayoutKey = _resolveEditingLayoutIdentity(
      data: geometry.data,
      layoutWidth: geometry.rect.width,
      locale: locale,
    );
    _clearEditingPainterLayoutCache();
    _resetVerticalCaretRun();
    _pendingTextDraftSync = _PendingTextDraftSync(
      elementId: interaction.elementId,
      text: nextText,
      previewRect: geometry.rect,
      sourceRect: interaction.rect,
      sourceData: interaction.draftData,
    );
    _syncPendingTextDraftOverlay(
      text: nextText,
      previewRect: geometry.rect,
      interaction: interaction,
    );
    _schedulePendingTextDraftSyncDispatch();
  }

  _TextDraftGeometry _resolveTextEditGeometryForDraft({
    required TextEditingState interaction,
    required String text,
    required Locale? locale,
  }) {
    final nextData = interaction.draftData.copyWith(text: text);
    final geometry = resolveTextEditingGeometry(
      origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
      currentRect: interaction.rect,
      data: nextData,
      textMetricsService: widget.store.context.textMetricsService,
      allowShrinkHeight: true,
      localeTag: locale?.toLanguageTag(),
    );
    final layout = layoutText(
      data: nextData,
      maxWidth: geometry.rect.width,
      locale: locale,
    );
    return _TextDraftGeometry(
      data: nextData,
      rect: geometry.rect,
      layout: layout,
    );
  }

  _PendingTextDraftSync _resolvePendingTextDraftSyncForInteraction({
    required TextEditingState interaction,
    required _PendingTextDraftSync pending,
  }) {
    if (pending.sourceRect == interaction.rect &&
        identical(pending.sourceData, interaction.draftData)) {
      return pending;
    }
    final locale = Localizations.maybeLocaleOf(context);
    final geometry = _resolveTextEditGeometryForDraft(
      interaction: interaction,
      text: pending.text,
      locale: locale,
    );
    _editingTextLayout = geometry.layout;
    _editingTextLayoutKey = _resolveEditingLayoutIdentity(
      data: geometry.data,
      layoutWidth: geometry.rect.width,
      locale: locale,
    );
    _clearEditingPainterLayoutCache();
    return pending.copyWith(
      previewRect: geometry.rect,
      sourceRect: interaction.rect,
      sourceData: interaction.draftData,
    );
  }

  void _syncPendingTextDraftOverlay({
    required String text,
    required DrawRect previewRect,
    required TextEditingState interaction,
  }) {
    final snapshot = _textOverlayNotifier.value;
    if (snapshot == null || snapshot.elementId != interaction.elementId) {
      return;
    }
    final nextSnapshot = snapshot.copyWith(
      data: snapshot.data.copyWith(text: text),
      rect: previewRect,
    );
    _setTextOverlaySnapshot(nextSnapshot);
  }

  void _schedulePendingTextDraftSyncDispatch() {
    final pending = _pendingTextDraftSync;
    if (pending == null) {
      _cancelPendingTextDraftSyncDispatch();
      return;
    }

    final now = DateTime.now();
    final last = _lastTextDraftSyncAt;
    if (last == null || now.difference(last) >= _textDraftSyncMinInterval) {
      _cancelPendingTextDraftSyncDispatch();
      _textDraftDispatcher.dispatch(pending);
      return;
    }

    final delay = _textDraftSyncMinInterval - now.difference(last);
    final timer = _textDraftSyncTimer;
    if (timer != null && timer.isActive) {
      return;
    }
    _textDraftSyncTimer = Timer(delay, () {
      _textDraftSyncTimer = null;
      if (!mounted || _pendingTextDraftSync == null) {
        return;
      }
      _textDraftDispatcher.dispatch(_pendingTextDraftSync!);
    });
  }

  void _cancelPendingTextDraftSyncDispatch() {
    _textDraftSyncTimer?.cancel();
    _textDraftSyncTimer = null;
  }

  Future<void> _dispatchPendingTextDraftSync(
    _PendingTextDraftSync pending,
  ) async {
    final interaction = widget.store.state.application.interaction;
    if (interaction is! TextEditingState ||
        interaction.elementId != pending.elementId) {
      if (_pendingTextDraftSync == pending) {
        _pendingTextDraftSync = null;
        _cancelPendingTextDraftSyncDispatch();
      }
      return;
    }

    if (_isSameTextValue(interaction.draftData.text, pending.text)) {
      if (_pendingTextDraftSync == pending) {
        _pendingTextDraftSync = null;
        _cancelPendingTextDraftSyncDispatch();
      }
      return;
    }

    final resolvedPending = _resolvePendingTextDraftSyncForInteraction(
      interaction: interaction,
      pending: pending,
    );
    if (_pendingTextDraftSync == pending && resolvedPending != pending) {
      _pendingTextDraftSync = resolvedPending;
      _schedulePendingTextDraftSyncDispatch();
    }

    _lastTextDraftSyncAt = DateTime.now();
    await widget.store.dispatch(
      UpdateTextEdit(
        text: resolvedPending.text,
        rect: resolvedPending.previewRect,
      ),
    );
  }

  Future<void> _flushPendingTextDraftSync() async {
    _cancelPendingTextDraftSyncDispatch();
    await _textDraftDispatcher.flush();
    final pending = _pendingTextDraftSync;
    if (pending == null) {
      return;
    }
    await _dispatchPendingTextDraftSync(pending);
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
    return lineMetrics.length - 1;
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
    required FlutterTextLayoutMetrics layout,
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

  double _quantizeEditingLayoutWidth(double width) =>
      (width * 10).roundToDouble() / 10;

  bool _shouldPaintTextDecorations({
    required TextData data,
    required double opacity,
  }) {
    final backgroundOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    if (backgroundOpacity > 0) {
      return true;
    }
    final strokeOpacity = (data.strokeColor.a * opacity).clamp(0.0, 1.0);
    return data.strokeWidth > 0 && strokeOpacity > 0;
  }

  void _refreshPointerVisualsForState(DrawState state) {
    final position = _lastPointerPosition;
    if (position != null && _isPointerInside) {
      if (!mounted) {
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
      _updateCursorAndHoverForPosition(position);
      return;
    }

    _refreshCursorAndClearHoverForState(state);
  }

  void _refreshCursorAndClearHoverForState(DrawState state) {
    final cursor = _resolveCursorForState(state, _lastPointerPosition);
    if (!mounted) {
      _cursor = cursor;
      _hoveredSelectionElementId = null;
      _hoveredBindingElementId = null;
      _hoveredArrowHandle = null;
      return;
    }
    _updateCursorIfChanged(cursor);
    _clearHoverState();
  }

  void _handleStateChange(DrawState state) {
    _syncTextEditingOverlayState(state);
    _refreshPointerVisualsForState(state);
    _refreshCanvasSnapshot(state);
  }

  void _handleConfigChange(DrawConfig _) {
    if (!mounted) {
      return;
    }
    _cachedInputSelectionConfigSource = null;
    _cachedInputSelectionConfig = null;
    _cachedInputSelectionScale = null;

    _refreshPointerVisualsForState(widget.store.state);
    _refreshCanvasSnapshot(widget.store.state);
  }

  void _handleTextRenderingCacheInvalidation() {
    if (!mounted) {
      return;
    }
    _clearEditingTextLayoutCache();
    _clearEditingPainterLayoutCache();
    unawaited(_refreshAutoResizeTextLayoutsAfterFontLoad());
    _refreshCanvasSnapshot(widget.store.state);
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
    await _flushPendingTextDraftSync();
    final interaction = widget.store.state.application.interaction;
    final actions = resolveToolChangeResetActions(
      interaction: interaction,
      includeClearSelection: true,
    );
    for (final action in actions) {
      await widget.store.dispatch(action);
    }
  }
}

@immutable
class _CanvasRenderInputs {
  const _CanvasRenderInputs({
    required this.previewElements,
    required this.creatingSnapshot,
    required this.highlightMaskConfig,
    required this.watermarkConfig,
    required this.textRenderingCacheRevision,
  });

  final Map<String, ElementState> previewElements;
  final CreatingElementSnapshot? creatingSnapshot;
  final HighlightMaskConfig highlightMaskConfig;
  final WatermarkConfig watermarkConfig;
  final int textRenderingCacheRevision;
}

@immutable
class _CanvasSnapshot {
  const _CanvasSnapshot({required this.stateView, required this.renderKey});

  final DrawStateView stateView;
  final SceneCanvasRenderKey renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CanvasSnapshot && other.renderKey == renderKey;

  @override
  int get hashCode => renderKey.hashCode;
}

@immutable
class _TextEditingOverlaySnapshot {
  const _TextEditingOverlaySnapshot({
    required this.elementId,
    required this.data,
    required this.rect,
    required this.isNew,
    required this.rotation,
    required this.opacity,
    required this.initialCursorPosition,
  });

  factory _TextEditingOverlaySnapshot.fromInteraction(
    TextEditingState interaction,
  ) => _TextEditingOverlaySnapshot(
    elementId: interaction.elementId,
    data: interaction.draftData,
    rect: interaction.rect,
    isNew: interaction.isNew,
    rotation: interaction.rotation,
    opacity: interaction.opacity,
    initialCursorPosition: interaction.initialCursorPosition,
  );

  final String elementId;
  final TextData data;
  final DrawRect rect;
  final bool isNew;
  final double rotation;
  final double opacity;
  final DrawPoint? initialCursorPosition;

  _TextEditingOverlaySnapshot copyWith({TextData? data, DrawRect? rect}) =>
      _TextEditingOverlaySnapshot(
        elementId: elementId,
        data: data ?? this.data,
        rect: rect ?? this.rect,
        isNew: isNew,
        rotation: rotation,
        opacity: opacity,
        initialCursorPosition: initialCursorPosition,
      );

  TextEditingState toInteractionState() => TextEditingState(
    elementId: elementId,
    draftData: data,
    rect: rect,
    isNew: isNew,
    opacity: opacity,
    rotation: rotation,
    initialCursorPosition: initialCursorPosition,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextEditingOverlaySnapshot &&
          other.elementId == elementId &&
          identical(other.data, data) &&
          other.rect == rect &&
          other.isNew == isNew &&
          other.rotation == rotation &&
          other.opacity == opacity &&
          other.initialCursorPosition == initialCursorPosition;

  @override
  int get hashCode => Object.hash(
    elementId,
    identityHashCode(data),
    rect,
    isNew,
    rotation,
    opacity,
    initialCursorPosition,
  );
}

@immutable
class _EditingTextOverlayPainter extends CustomPainter {
  const _EditingTextOverlayPainter({
    required this.elementId,
    required this.data,
    required this.opacity,
    required this.layout,
    required this.cacheRevision,
    this.locale,
  });

  static const _renderer = TextRenderer();

  final String elementId;
  final TextData data;
  final double opacity;
  final FlutterTextLayoutMetrics layout;
  final int cacheRevision;
  final Locale? locale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final element = ElementState(
      id: elementId,
      rect: DrawRect(maxX: size.width, maxY: size.height),
      rotation: 0,
      opacity: opacity,
      zIndex: 0,
      data: data,
    );
    _renderer.renderWithOptions(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
      locale: locale,
      precomputedLayout: layout,
      renderFill: false,
    );
  }

  @override
  bool shouldRepaint(covariant _EditingTextOverlayPainter oldDelegate) =>
      oldDelegate.elementId != elementId ||
      oldDelegate.data != data ||
      oldDelegate.opacity != opacity ||
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.cacheRevision != cacheRevision ||
      oldDelegate.locale != locale;
}

@immutable
class _PendingTextDraftSync {
  const _PendingTextDraftSync({
    required this.elementId,
    required this.text,
    required this.previewRect,
    required this.sourceRect,
    required this.sourceData,
  });

  final String elementId;
  final String text;
  final DrawRect previewRect;
  final DrawRect sourceRect;
  final TextData sourceData;

  _PendingTextDraftSync copyWith({
    String? elementId,
    String? text,
    DrawRect? previewRect,
    DrawRect? sourceRect,
    TextData? sourceData,
  }) => _PendingTextDraftSync(
    elementId: elementId ?? this.elementId,
    text: text ?? this.text,
    previewRect: previewRect ?? this.previewRect,
    sourceRect: sourceRect ?? this.sourceRect,
    sourceData: sourceData ?? this.sourceData,
  );
}

@immutable
class _TextDraftGeometry {
  const _TextDraftGeometry({
    required this.data,
    required this.rect,
    required this.layout,
  });

  final TextData data;
  final DrawRect rect;
  final FlutterTextLayoutMetrics layout;
}

@immutable
class _EditingLayoutIdentity {
  const _EditingLayoutIdentity({
    required this.textToken,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.layoutWidth,
    required this.localeTag,
  });

  final String textToken;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final double layoutWidth;
  final String? localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EditingLayoutIdentity &&
          identical(other.textToken, textToken) &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.layoutWidth == layoutWidth &&
          other.localeTag == localeTag;

  @override
  int get hashCode => Object.hash(
    identityHashCode(textToken),
    fontSize,
    fontFamily,
    horizontalAlign,
    layoutWidth,
    localeTag,
  );
}
