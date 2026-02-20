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
  SelectPlugin({
    this.currentToolTypeId,
    this.isSelectionToolActive = true,
    InputRoutingPolicy? routingPolicy,
  }) : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
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
  bool isSelectionToolActive;

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
  bool canHandle(InputEvent _, DrawState state) =>
      !_isSelectionBehaviorDisabled && _routingPolicy.allowSelection(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) => switch (event) {
    PointerDownInputEvent() => _handlePointerDown(event),
    PointerMoveInputEvent() => _handlePointerMove(event),
    PointerUpInputEvent() => _handlePointerUp(),
    PointerCancelInputEvent() => _handlePointerCancel(),
    _ => Future<PluginResult>.value(unhandled()),
  };

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
      final now = DateTime.now();
      final data = _arrowDataForElement(stateView, intent.elementId);
      if (data == null) {
        _clearArrowHandleClickState();
      } else {
        final handle = _resolveArrowHandleForIntent(
          intent: intent,
          position: position,
          data: data,
        );
        final canDoubleClick = _isArrowHandleDoubleClickCandidate(
          handle: handle,
          data: data,
        );
        if (canDoubleClick && _isDoubleClick(handle, position, now)) {
          _clearArrowHandleClickState();
          final doubleClickIntent = StartArrowPointIntent(
            elementId: intent.elementId,
            pointKind: intent.pointKind,
            pointIndex: intent.pointIndex,
            isDoubleClick: true,
          );
          await _executeIntent(doubleClickIntent, position, editModifiers);
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

    await _executeIntent(intent, position, editModifiers);
    return handled(message: 'Selection handled');
  }

  Future<PluginResult> _handlePointerMove(PointerMoveInputEvent event) async {
    final interaction = state.application.interaction;

    if (interaction is! DragPendingState) {
      return unhandled();
    }

    final pendingIntent = interaction.intent;
    final pointerDownPosition = interaction.pointerDownPosition;
    final thresholdSquared = _dragStartThreshold * _dragStartThreshold;

    if (pointerDownPosition.distanceSquared(event.position) >=
        thresholdSquared) {
      await dispatch(const ClearDragPending());

      if (state.domain.hasSelection) {
        final (elementId, addToSelection) = switch (pendingIntent) {
          PendingSelectIntent(:final elementId, :final addToSelection) => (
            elementId,
            addToSelection,
          ),
          PendingMoveIntent() => (
            state.domain.selection.selectedIds.first,
            false,
          ),
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

  Future<PluginResult> _handlePointerUp() async {
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

  Future<void> _executeIntent(
    EditIntent intent,
    DrawPoint position,
    EditModifiers modifiers,
  ) async {
    switch (intent) {
      case SelectIntent():
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
        return;
      case StartMoveIntent():
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
        return;
      case BoxSelectIntent():
        await dispatch(StartBoxSelect(startPosition: intent.startPosition));
        return;
      case ClearSelectionIntent():
        await dispatch(const ClearSelection());
        return;
      default:
        await dispatch(
          EditIntentAction(
            intent: intent,
            position: position,
            modifiers: modifiers,
          ),
        );
        return;
    }
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

  Future<void> _updateEditFromEvent(PointerMoveInputEvent event) => dispatch(
    UpdateEdit(
      currentPosition: event.position,
      modifiers: event.modifiers.toEditModifiers(),
    ),
  );

  EditIntent? _filterIntentForTool(EditIntent? intent) {
    if (intent == null || _isSelectionBehaviorDisabled) {
      return null;
    }
    if (currentToolTypeId == null) {
      return intent;
    }

    if (intent is BoxSelectIntent) {
      // Box selection should only be allowed when selection tool is active.
      // When another tool is active, convert to clear selection intent.
      return const ClearSelectionIntent();
    }

    if (intent
        case SelectIntent(:final elementId) ||
            StartMoveIntent(:final elementId)) {
      return _isSelectableElement(elementId) ? intent : null;
    }

    return intent;
  }

  bool get _isSelectionBehaviorDisabled =>
      currentToolTypeId == null && !isSelectionToolActive;

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

  bool _isBoundSerialText(String textElementId) =>
      state.domain.document.boundTextIds.contains(textElementId);

  ArrowLikeData? _arrowDataForElement(
    DrawStateView stateView,
    String elementId,
  ) {
    final element = stateView.state.domain.document.getElementById(elementId);
    final data = element?.data;
    if (data is ArrowLikeData) {
      return data;
    }
    return null;
  }

  ArrowPointHandle _resolveArrowHandleForIntent({
    required StartArrowPointIntent intent,
    required DrawPoint position,
    required ArrowLikeData data,
  }) {
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
