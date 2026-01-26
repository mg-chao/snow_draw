import '../../actions/draw_actions.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../utils/hit_test.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that handles arrow creation (single- and multi-point).
class ArrowCreatePlugin extends DrawInputPlugin {
  ArrowCreatePlugin({
    required this.currentToolTypeId,
    InputRoutingPolicy? routingPolicy,
  }) : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
       super(
         id: 'arrow_create',
         name: 'Arrow Create Plugin',
         priority: 9,
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

  final InputRoutingPolicy _routingPolicy;
  DrawStateViewBuilder? _stateViewBuilder;

  ElementTypeId<ElementData>? currentToolTypeId;

  DrawPoint? _pointerDownPosition;
  var _isDragging = false;
  var _isMultiPoint = false;
  var _justFinishedDragCreate = false;
  DateTime? _lastClickTime;
  DrawPoint? _lastClickPosition;

  bool get _isArrowToolActive => currentToolTypeId == ArrowData.typeIdToken;

  @override
  Future<void> onLoad(PluginContext context) async {
    await super.onLoad(context);
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: drawContext.editOperations,
    );
  }

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      _isArrowToolActive && _routingPolicy.allowCreate(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    _syncInternalState();

    if (event is PointerDownInputEvent) {
      return _handlePointerDown(event);
    }
    if (event is PointerMoveInputEvent) {
      return _handlePointerMove(event);
    }
    if (event is PointerHoverInputEvent) {
      return _handlePointerHover(event);
    }
    if (event is PointerUpInputEvent) {
      return _handlePointerUp(event);
    }
    if (event is PointerCancelInputEvent) {
      return _handlePointerCancel();
    }
    return unhandled();
  }

  @override
  void reset() {
    _resetInteractionState();
  }

  Future<PluginResult> _handlePointerDown(PointerDownInputEvent event) async {
    if (!_isArrowToolActive) {
      return unhandled();
    }

    if (state.application.isCreating) {
      if (!_isArrowCreating(state)) {
        return unhandled();
      }
      _pointerDownPosition = event.position;
      _isDragging = false;
      return handled(message: 'Arrow create point start');
    }

    if (!_shouldStartCreate(event.position)) {
      return unhandled();
    }

    // Clear all state before starting a new arrow to ensure clean slate
    _resetInteractionState();
    _pointerDownPosition = event.position;
    _justFinishedDragCreate = false; // Clear flag when starting new creation

    await dispatch(
      CreateElement(
        typeId: ArrowData.typeIdToken,
        position: event.position,
        maintainAspectRatio: event.modifiers.shift,
        createFromCenter: event.modifiers.alt,
        snapOverride: event.modifiers.control,
      ),
    );
    return handled(message: 'Arrow create started');
  }

  Future<PluginResult> _handlePointerMove(PointerMoveInputEvent event) async {
    if (!_isArrowCreating(state)) {
      return unhandled();
    }

    final downPosition = _pointerDownPosition;
    if (downPosition != null && !_isDragging) {
      final threshold = selectionConfig.interaction.dragThreshold;
      if (threshold == 0 ||
          downPosition.distanceSquared(event.position) >=
              threshold * threshold) {
        _isDragging = true;
      }
    }

    await dispatch(
      UpdateCreatingElement(
        currentPosition: event.position,
        maintainAspectRatio: event.modifiers.shift,
        createFromCenter: event.modifiers.alt,
        snapOverride: event.modifiers.control,
      ),
    );
    return handled(message: 'Arrow create updated');
  }

  Future<PluginResult> _handlePointerHover(PointerHoverInputEvent event) async {
    if (!_isArrowCreating(state) || !_isMultiPoint) {
      return unhandled();
    }
    await dispatch(
      UpdateCreatingElement(
        currentPosition: event.position,
        maintainAspectRatio: event.modifiers.shift,
        createFromCenter: event.modifiers.alt,
        snapOverride: event.modifiers.control,
      ),
    );
    return handled(message: 'Arrow create hover updated');
  }

  Future<PluginResult> _handlePointerUp(PointerUpInputEvent event) async {
    if (!_isArrowCreating(state)) {
      return unhandled();
    }

    final wasDragging = _isDragging;
    final wasMultiPoint = _isMultiPoint;
    _pointerDownPosition = null;
    _isDragging = false;

    // Only finish on drag if the user actually dragged a meaningful distance
    if (wasDragging && !wasMultiPoint) {
      await dispatch(const FinishCreateElement());
      _resetInteractionState();
      _justFinishedDragCreate =
          true; // Set flag to allow immediate next creation
      return handled(message: 'Arrow create finished');
    }

    final now = DateTime.now();
    if (!wasMultiPoint) {
      // First click after initial point - enter multi-point mode
      _isMultiPoint = true;
      _recordClick(event.position, now);
      return handled(message: 'Arrow create multi-point started');
    }

    // Check for double-click BEFORE adding the point
    final isDoubleClick = !wasDragging && _isDoubleClick(event.position, now);

    if (isDoubleClick) {
      // Double-click detected - finish without adding another point
      await dispatch(const FinishCreateElement());
      _resetInteractionState();
      return handled(message: 'Arrow create finished (double-click)');
    }

    // Single click - add the point and continue
    await dispatch(
      AddArrowPoint(
        position: event.position,
        snapOverride: event.modifiers.control,
      ),
    );

    _recordClick(event.position, now);
    return handled(message: 'Arrow create point added');
  }

  Future<PluginResult> _handlePointerCancel() async {
    if (_isArrowCreating(state)) {
      await dispatch(const CancelCreateElement());
      _resetInteractionState();
      return consumed(message: 'Arrow create canceled');
    }
    return unhandled();
  }

  bool _shouldStartCreate(DrawPoint position) {
    final tolerance = selectionConfig.interaction.handleTolerance;
    final hitResult = hitTest.test(
      stateView: _stateView,
      position: position,
      config: selectionConfig,
      registry: drawContext.elementRegistry,
      tolerance: tolerance,
      filterTypeId: ArrowData.typeIdToken,
    );

    // If we hit an arrow element, defer to selection
    if (hitResult.isHit) {
      return false;
    }

    // If there's a selection and clicking on blank area, check context:
    // - If we just finished drag-creating, allow immediate next creation
    // - Otherwise, let the selection plugin handle deselection first
    if (state.domain.hasSelection && !_justFinishedDragCreate) {
      return false;
    }

    // No arrow hit and
    // (no selection OR just finished drag create) - allow creation
    return true;
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

  void _syncInternalState() {
    if (!_isArrowCreating(state)) {
      _resetInteractionState();
    }
  }

  void _resetInteractionState() {
    _pointerDownPosition = null;
    _isDragging = false;
    _isMultiPoint = false;
    _justFinishedDragCreate = false;
    _clearClickState();
  }

  bool _isArrowCreating(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return false;
    }
    return interaction.element.data is ArrowData;
  }

  DrawStateView get _stateView {
    final builder = _stateViewBuilder;
    if (builder == null) {
      throw StateError('ArrowCreatePlugin has not been loaded yet');
    }
    return builder.build(state);
  }
}
