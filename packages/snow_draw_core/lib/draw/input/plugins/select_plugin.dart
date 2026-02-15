import '../../actions/draw_actions.dart';
import '../../edit/core/edit_modifiers.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../types/element_style.dart';
import '../../utils/edit_intent_detector.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that handles selection and intent detection.
class SelectPlugin extends DrawInputPlugin {
  SelectPlugin({this.currentToolTypeId, InputRoutingPolicy? routingPolicy})
    : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
      super(
        id: 'select',
        name: 'Select Plugin',
        priority: 20,
        supportedEventTypes: {
          PointerDownInputEvent,
          PointerMoveInputEvent,
          PointerUpInputEvent,
          PointerCancelInputEvent,
        },
      );
  static const _doubleClickThreshold = Duration(milliseconds: 500);
  static const double _doubleClickToleranceMultiplier = 2;
  final InputRoutingPolicy _routingPolicy;
  DrawStateViewBuilder? _stateViewBuilder;
  ElementTypeId<ElementData>? currentToolTypeId;

  DateTime? _lastArrowHandleClickTime;
  DrawPoint? _lastArrowHandleClickPosition;
  ArrowPointHandle? _lastArrowHandleClickHandle;

  @override
  Future<void> onLoad(PluginContext context) async {
    await super.onLoad(context);
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: drawContext.editOperations,
    );
  }

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      _routingPolicy.allowSelection(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerDownInputEvent) {
      return _handlePointerDown(event);
    }
    if (event is PointerMoveInputEvent) {
      return _handlePointerMove(event);
    }
    if (event is PointerUpInputEvent) {
      return _handlePointerUp(event);
    }
    if (event is PointerCancelInputEvent) {
      return _handlePointerCancel();
    }
    return unhandled();
  }

  DrawStateView get _stateView {
    final builder = _stateViewBuilder;
    if (builder == null) {
      throw StateError('SelectPlugin has not been loaded yet');
    }
    return builder.build(state);
  }

  double get _dragStartThreshold => selectionConfig.interaction.dragThreshold;

  Future<PluginResult> _handlePointerDown(PointerDownInputEvent event) async {
    final position = event.position;
    final modifiers = event.modifiers;
    final stateView = _stateView;

    final intent = _filterIntentForTool(
      editIntentDetector.detectIntent(
        stateView: stateView,
        position: position,
        isShiftPressed: modifiers.shift,
        isAltPressed: modifiers.alt,
        config: selectionConfig,
        registry: drawContext.elementRegistry,
        filterTypeId: currentToolTypeId,
      ),
    );
    if (intent == null) {
      return unhandled();
    }

    final editModifiers = modifiers.toEditModifiers();

    if (intent is StartArrowPointIntent) {
      final handle = _resolveArrowHandleForIntent(
        stateView: stateView,
        intent: intent,
        position: position,
      );
      final now = DateTime.now();
      final element = stateView.state.domain.document.getElementById(
        intent.elementId,
      );
      final data = element?.data is ArrowLikeData
          ? element!.data as ArrowLikeData
          : null;
      final canDoubleClick =
          handle != null &&
          data != null &&
          _isArrowHandleDoubleClickCandidate(handle: handle, data: data);
      if (canDoubleClick && _isDoubleClick(handle, position, now)) {
        _clearArrowHandleClickState();
        final doubleClickIntent = StartArrowPointIntent(
          elementId: intent.elementId,
          pointKind: intent.pointKind,
          pointIndex: intent.pointIndex,
          isDoubleClick: true,
        );
        final handledIntent = await _executeIntent(
          doubleClickIntent,
          position,
          editModifiers,
        );
        if (!handledIntent) {
          return unhandled();
        }
        return handled(
          message: handle.isFixed
              ? 'Arrow segment released'
              : 'Arrow point deleted',
        );
      }
      if (canDoubleClick) {
        _recordArrowHandleClick(handle, position, now);
      } else {
        _clearArrowHandleClickState();
      }
    } else {
      _clearArrowHandleClickState();
    }

    if (intent is SelectIntent && intent.deferSelectionForDrag) {
      await dispatch(
        SetDragPending(
          pointerDownPosition: position,
          intent: PendingSelectIntent(
            elementId: intent.elementId,
            addToSelection: intent.addToSelection,
          ),
        ),
      );
      return handled(message: 'Pending select');
    }

    final handledIntent = await _executeIntent(intent, position, editModifiers);
    return handledIntent ? handled(message: 'Selection handled') : unhandled();
  }

  Future<PluginResult> _handlePointerMove(PointerMoveInputEvent event) async {
    final interaction = state.application.interaction;

    if (interaction is! DragPendingState) {
      return unhandled();
    }

    final pendingIntent = interaction.intent;
    final pointerDownPosition = interaction.pointerDownPosition;
    final dx = event.position.x - pointerDownPosition.x;
    final dy = event.position.y - pointerDownPosition.y;
    final threshold = _dragStartThreshold;

    if ((dx * dx + dy * dy) >= (threshold * threshold)) {
      await dispatch(const ClearDragPending());

      if (state.domain.hasSelection) {
        final elementId = switch (pendingIntent) {
          PendingSelectIntent(:final elementId) => elementId,
          PendingMoveIntent() => state.domain.selection.selectedIds.first,
        };
        final addToSelection = switch (pendingIntent) {
          PendingSelectIntent(:final addToSelection) => addToSelection,
          PendingMoveIntent() => false,
        };

        final didStart = await _dispatchStartEditForIntent(
          intent: StartMoveIntent(
            elementId: elementId,
            addToSelection: addToSelection,
          ),
          position: pointerDownPosition,
          modifiers: event.modifiers.toEditModifiers(),
        );
        if (didStart) {
          await _updateEditFromEvent(event);
        }
      }
    }

    return handled(message: 'Pending drag');
  }

  Future<PluginResult> _handlePointerUp(PointerUpInputEvent event) async {
    final interaction = state.application.interaction;

    if (interaction is! DragPendingState) {
      return unhandled();
    }

    final pendingIntent = interaction.intent;
    if (pendingIntent is PendingSelectIntent) {
      await dispatch(
        SelectElement(
          elementId: pendingIntent.elementId,
          addToSelection: pendingIntent.addToSelection,
          position: interaction.pointerDownPosition,
        ),
      );
    }
    await dispatch(const ClearDragPending());
    return handled(message: 'Pending cleared');
  }

  Future<PluginResult> _handlePointerCancel() async {
    final interaction = state.application.interaction;

    if (interaction is DragPendingState) {
      await dispatch(const ClearDragPending());
      return consumed(message: 'Pending canceled');
    }

    return unhandled();
  }

  Future<bool> _executeIntent(
    EditIntent? intent,
    DrawPoint position,
    EditModifiers modifiers,
  ) async {
    if (intent == null) {
      return false;
    }

    if (intent case SelectIntent()) {
      await dispatch(
        SelectElement(
          elementId: intent.elementId,
          addToSelection: intent.addToSelection,
          position: position,
        ),
      );
      if (!intent.addToSelection) {
        await dispatch(
          SetDragPending(
            pointerDownPosition: position,
            intent: const PendingMoveIntent(),
          ),
        );
      }
      return true;
    }

    if (intent case StartMoveIntent()) {
      if (!state.domain.selection.selectedIds.contains(intent.elementId)) {
        await dispatch(
          SelectElement(
            elementId: intent.elementId,
            addToSelection: intent.addToSelection,
            position: position,
          ),
        );
      }
      await dispatch(
        SetDragPending(
          pointerDownPosition: position,
          intent: const PendingMoveIntent(),
        ),
      );
      return true;
    }

    if (intent case BoxSelectIntent()) {
      await dispatch(StartBoxSelect(startPosition: intent.startPosition));
      return true;
    }

    if (intent case ClearSelectionIntent()) {
      await dispatch(const ClearSelection());
      return true;
    }

    return _dispatchEditIntent(
      intent: intent,
      position: position,
      modifiers: modifiers,
    );
  }

  Future<bool> _dispatchStartEditForIntent({
    required EditIntent intent,
    required DrawPoint position,
    required EditModifiers modifiers,
  }) async {
    final wasEditing = state.application.isEditing;
    await dispatch(
      EditIntentAction(
        intent: intent,
        position: position,
        modifiers: modifiers,
      ),
    );
    return !wasEditing && state.application.isEditing;
  }

  Future<bool> _dispatchEditIntent({
    required EditIntent intent,
    required DrawPoint position,
    required EditModifiers modifiers,
  }) async {
    await dispatch(
      EditIntentAction(
        intent: intent,
        position: position,
        modifiers: modifiers,
      ),
    );
    return true;
  }

  Future<void> _updateEditFromEvent(PointerMoveInputEvent event) => dispatch(
    UpdateEdit(
      currentPosition: event.position,
      modifiers: event.modifiers.toEditModifiers(),
    ),
  );

  EditIntent? _filterIntentForTool(EditIntent? intent) {
    if (intent == null) {
      return null;
    }
    if (currentToolTypeId == null) {
      return intent;
    }

    switch (intent) {
      case SelectIntent(:final elementId):
      case StartMoveIntent(:final elementId):
        if (!_isSelectableElement(elementId)) {
          return null;
        }
      case BoxSelectIntent():
        // Box selection should only be allowed when selection tool is active.
        // When another tool is active, convert to clear selection intent.
        return const ClearSelectionIntent();
      default:
        break;
    }

    return intent;
  }

  bool _isSelectableElement(String elementId) {
    final toolTypeId = currentToolTypeId;
    if (toolTypeId == null) {
      return true;
    }
    final element = state.domain.document.getElementById(elementId);
    if (element == null) {
      return false;
    }
    if (element.typeId == toolTypeId) {
      return true;
    }
    if (toolTypeId == SerialNumberData.typeIdToken &&
        element.data is TextData) {
      return _isBoundSerialText(elementId);
    }
    return false;
  }

  bool _isBoundSerialText(String textElementId) {
    for (final element in state.domain.document.elements) {
      final data = element.data;
      if (data is SerialNumberData && data.textElementId == textElementId) {
        return true;
      }
    }
    return false;
  }

  ArrowPointHandle? _resolveArrowHandleForIntent({
    required DrawStateView stateView,
    required StartArrowPointIntent intent,
    required DrawPoint position,
  }) {
    final element = stateView.state.domain.document.getElementById(
      intent.elementId,
    );
    if (element == null || element.data is! ArrowLikeData) {
      return null;
    }
    final data = element.data as ArrowLikeData;
    final isFixed =
        data.arrowType == ArrowType.elbow &&
        intent.pointKind == ArrowPointKind.addable &&
        (data.fixedSegments?.any(
              (segment) => segment.index == intent.pointIndex + 1,
            ) ??
            false);
    return ArrowPointHandle(
      elementId: intent.elementId,
      kind: intent.pointKind,
      index: intent.pointIndex,
      position: position,
      isFixed: isFixed,
    );
  }

  bool _isArrowHandleDoubleClickCandidate({
    required ArrowPointHandle handle,
    required ArrowLikeData data,
  }) {
    if (handle.isFixed) {
      return true;
    }
    if (handle.kind != ArrowPointKind.turning) {
      return false;
    }
    final pointCount = data.points.length;
    return handle.index > 0 && handle.index < pointCount - 1;
  }

  bool _isDoubleClick(
    ArrowPointHandle handle,
    DrawPoint position,
    DateTime now,
  ) {
    final lastTime = _lastArrowHandleClickTime;
    final lastPosition = _lastArrowHandleClickPosition;
    final lastHandle = _lastArrowHandleClickHandle;
    if (lastTime == null || lastPosition == null || lastHandle == null) {
      return false;
    }
    if (now.difference(lastTime) > _doubleClickThreshold) {
      return false;
    }
    if (lastHandle != handle) {
      return false;
    }
    final tolerance =
        selectionConfig.interaction.handleTolerance *
        _doubleClickToleranceMultiplier;
    return lastPosition.distanceSquared(position) <= tolerance * tolerance;
  }

  void _recordArrowHandleClick(
    ArrowPointHandle handle,
    DrawPoint position,
    DateTime now,
  ) {
    _lastArrowHandleClickHandle = handle;
    _lastArrowHandleClickPosition = position;
    _lastArrowHandleClickTime = now;
  }

  void _clearArrowHandleClickState() {
    _lastArrowHandleClickHandle = null;
    _lastArrowHandleClickPosition = null;
    _lastArrowHandleClickTime = null;
  }
}
