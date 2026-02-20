import '../../actions/draw_actions.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/free_draw/free_draw_data.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../types/element_style.dart';
import '../../utils/hit_test.dart';
import '../input_event.dart';
import '../plugin_core.dart';
import '../pointer_sample_resampler.dart';

/// Plugin that handles element creation via the current tool.
class CreatePlugin extends DrawInputPlugin {
  CreatePlugin({
    required this.currentToolTypeId,
    InputRoutingPolicy? routingPolicy,
  }) : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
       super(
         id: 'create',
         name: 'Create Plugin',
         priority: 10,
         supportedEventTypes: {
           PointerDownInputEvent,
           PointerMoveInputEvent,
           PointerHoverInputEvent,
           PointerUpInputEvent,
           PointerCancelInputEvent,
         },
       );

  static const _doubleClickThreshold = Duration(milliseconds: 500);
  static const double _doubleClickToleranceMultiplier = 2;
  static const _maxFreeDrawBatchSamples = 96;

  final InputRoutingPolicy _routingPolicy;
  DrawStateViewBuilder? _stateViewBuilder;

  ElementTypeId<ElementData>? currentToolTypeId;

  DrawPoint? _pointerDownPosition;
  var _isDragging = false;
  var _isMultiPoint = false;
  DateTime? _lastClickTime;
  DrawPoint? _lastClickPosition;
  DrawPoint? _lastUpdatePosition;
  KeyModifiers? _lastUpdateModifiers;

  @override
  Future<void> onLoad(PluginContext context) async {
    await super.onLoad(context);
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: drawContext.editOperations,
    );
  }

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      _routingPolicy.allowCreate(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) {
    _syncInternalState();

    return switch (event) {
      PointerDownInputEvent() => _handlePointerDown(event),
      PointerMoveInputEvent() => _handlePointerMove(event),
      PointerHoverInputEvent() => _handlePointerHover(event),
      PointerUpInputEvent() => _handlePointerUp(event),
      PointerCancelInputEvent() => _handlePointerCancel(),
      _ => Future<PluginResult>.value(unhandled()),
    };
  }

  @override
  void reset() {
    currentToolTypeId = null;
    _resetPointCreationState();
  }

  Future<PluginResult> _handlePointerDown(PointerDownInputEvent event) async {
    if (state.application.isCreating) {
      if (_isPointCreating(state)) {
        _pointerDownPosition = event.position;
        _isDragging = false;
        return handled(message: 'Create point start');
      }
      await dispatch(const FinishCreateElement());
      return handled(message: 'Create finished');
    }

    final toolTypeId = currentToolTypeId;
    if (toolTypeId == null) {
      return unhandled();
    }

    if (!_shouldStartCreate(event.position, toolTypeId)) {
      return unhandled();
    }

    _resetPointCreationState();
    _pointerDownPosition = event.position;

    await dispatch(
      CreateElement(
        typeId: toolTypeId,
        position: event.position,
        maintainAspectRatio: event.modifiers.shift,
        createFromCenter: event.modifiers.alt,
        snapOverride: event.modifiers.control,
      ),
    );
    return handled(message: 'Create started');
  }

  Future<PluginResult> _handlePointerMove(PointerMoveInputEvent event) async {
    if (!state.application.isCreating) {
      return unhandled();
    }

    if (_isPointCreating(state)) {
      final downPosition = _pointerDownPosition;
      if (downPosition != null && !_isDragging) {
        final threshold = selectionConfig.interaction.dragThreshold;
        if (threshold == 0 ||
            downPosition.distanceSquared(event.position) >=
                threshold * threshold) {
          _isDragging = true;
        }
      }
    }

    final isFreeDrawCreating = _isFreeDrawCreating(state);
    final hasBatchedSamples =
        isFreeDrawCreating && event.sampleCount > 1 && !event.modifiers.shift;
    if (!_shouldDispatchCreatingUpdate(
      event.position,
      event.modifiers,
      hasBatchedSamples: hasBatchedSamples,
    )) {
      return handled(message: 'Create unchanged');
    }

    if (hasBatchedSamples) {
      final sampledPoints = resamplePointerSamples(
        sampledPoints: event.sampledPoints,
        maxSamples: _maxFreeDrawBatchSamples,
      );
      await dispatch(
        UpdateCreatingElementBatch.frozen(
          positions: sampledPoints,
          createFromCenter: event.modifiers.alt,
          snapOverride: event.modifiers.control,
        ),
      );
      return handled(message: 'Create updated (batched)');
    }

    await _dispatchCreatingUpdate(event.position, event.modifiers);
    return handled(message: 'Create updated');
  }

  Future<PluginResult> _handlePointerHover(PointerHoverInputEvent event) async {
    if (!_isPointCreating(state) || !_isMultiPoint) {
      return unhandled();
    }
    if (!_shouldDispatchCreatingUpdate(event.position, event.modifiers)) {
      return handled(message: 'Create hover unchanged');
    }
    await _dispatchCreatingUpdate(event.position, event.modifiers);
    return handled(message: 'Create hover updated');
  }

  Future<PluginResult> _handlePointerUp(PointerUpInputEvent event) async {
    if (!state.application.isCreating) {
      return unhandled();
    }

    if (!_isPointCreating(state)) {
      await dispatch(const FinishCreateElement());
      return handled(message: 'Create finished');
    }

    final wasDragging = _isDragging;
    final wasMultiPoint = _isMultiPoint;
    final downPosition = _pointerDownPosition;
    _pointerDownPosition = null;
    _isDragging = false;

    // Only finish on drag if the user actually dragged a meaningful distance
    final minCreateSize = drawContext.config.element.minCreateSize;
    final wasMeaningfulDrag =
        wasDragging &&
        downPosition != null &&
        downPosition.distanceSquared(event.position) >=
            minCreateSize * minCreateSize;
    if (wasMeaningfulDrag && !wasMultiPoint) {
      await dispatch(const FinishCreateElement());
      _resetPointCreationState();
      return handled(message: 'Create finished');
    }

    final now = DateTime.now();
    if (!wasMultiPoint) {
      _isMultiPoint = true;
      _recordClick(event.position, now);
      return handled(message: 'Create multi-point started');
    }

    final isDoubleClick =
        !wasMeaningfulDrag && _isDoubleClick(event.position, now);

    if (_isElbowArrowCreating(state)) {
      await _dispatchCreatingUpdate(event.position, event.modifiers);
      await dispatch(const FinishCreateElement());
      _resetPointCreationState();
      return handled(message: 'Create finished (elbow)');
    }

    if (isDoubleClick) {
      await dispatch(const FinishCreateElement());
      _resetPointCreationState();
      return handled(message: 'Create finished (double-click)');
    }

    await dispatch(
      AddArrowPoint(
        position: event.position,
        snapOverride: event.modifiers.control,
      ),
    );
    _recordClick(event.position, now);
    return handled(message: 'Create point added');
  }

  Future<PluginResult> _handlePointerCancel() async {
    if (!state.application.isCreating) {
      return unhandled();
    }
    await dispatch(const CancelCreateElement());
    _resetPointCreationState();
    return consumed(message: 'Create canceled');
  }

  bool _shouldStartCreate(
    DrawPoint position,
    ElementTypeId<ElementData> toolTypeId,
  ) {
    final tolerance = selectionConfig.interaction.handleTolerance;
    final hitResult = hitTest.test(
      stateView: _stateView,
      position: position,
      config: selectionConfig,
      registry: drawContext.elementRegistry,
      tolerance: tolerance,
      filterTypeId: toolTypeId,
    );
    return !hitResult.isHit && !state.domain.hasSelection;
  }

  bool _isPointCreating(DrawState state) {
    final interaction = state.application.interaction;
    return interaction is CreatingState && interaction.isPointCreation;
  }

  bool _isFreeDrawCreating(DrawState state) {
    final interaction = state.application.interaction;
    return interaction is CreatingState &&
        interaction.elementData is FreeDrawData;
  }

  bool _isElbowArrowCreating(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return false;
    }
    final data = interaction.elementData;
    return data is ArrowLikeData && data.arrowType == ArrowType.elbow;
  }

  bool _isDoubleClick(DrawPoint position, DateTime now) {
    final lastTime = _lastClickTime;
    final lastPosition = _lastClickPosition;
    if (lastTime == null || lastPosition == null) {
      return false;
    }
    if (now.difference(lastTime) > _doubleClickThreshold) {
      return false;
    }
    final tolerance =
        selectionConfig.interaction.handleTolerance *
        _doubleClickToleranceMultiplier;
    return lastPosition.distanceSquared(position) <= tolerance * tolerance;
  }

  void _recordClick(DrawPoint position, DateTime now) {
    _lastClickPosition = position;
    _lastClickTime = now;
  }

  void _clearClickState() {
    _lastClickTime = null;
    _lastClickPosition = null;
  }

  bool _shouldDispatchCreatingUpdate(
    DrawPoint position,
    KeyModifiers modifiers, {
    bool hasBatchedSamples = false,
  }) {
    final previousPosition = _lastUpdatePosition;
    if (!hasBatchedSamples &&
        previousPosition != null &&
        previousPosition.x == position.x &&
        previousPosition.y == position.y &&
        _lastUpdateModifiers == modifiers) {
      return false;
    }
    _lastUpdatePosition = position;
    _lastUpdateModifiers = modifiers;
    return true;
  }

  Future<void> _dispatchCreatingUpdate(
    DrawPoint position,
    KeyModifiers modifiers,
  ) => dispatch(
    UpdateCreatingElement(
      currentPosition: position,
      maintainAspectRatio: modifiers.shift,
      createFromCenter: modifiers.alt,
      snapOverride: modifiers.control,
    ),
  );

  void _syncInternalState() {
    if (_isPointCreating(state)) {
      return;
    }

    _resetPointCreationSessionState();
    if (!state.application.isCreating) {
      _resetUpdateSignature();
    }
  }

  void _resetPointCreationState() {
    _resetPointCreationSessionState();
    _resetUpdateSignature();
  }

  void _resetPointCreationSessionState() {
    _pointerDownPosition = null;
    _isDragging = false;
    _isMultiPoint = false;
    _clearClickState();
  }

  void _resetUpdateSignature() {
    _lastUpdatePosition = null;
    _lastUpdateModifiers = null;
  }

  DrawStateView get _stateView {
    final builder = _stateViewBuilder;
    if (builder == null) {
      throw StateError('CreatePlugin has not been loaded yet');
    }
    return builder.build(state);
  }
}
