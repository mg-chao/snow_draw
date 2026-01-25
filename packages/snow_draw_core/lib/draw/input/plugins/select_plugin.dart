import '../../actions/draw_actions.dart';
import '../../edit/core/edit_modifiers.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../utils/edit_intent_detector.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that handles selection and intent detection.
class SelectPlugin extends DrawInputPlugin {
  SelectPlugin({
    this.currentToolTypeId,
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
  final InputRoutingPolicy _routingPolicy;
  DrawStateViewBuilder? _stateViewBuilder;
  ElementTypeId<ElementData>? currentToolTypeId;

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

    final editModifiers = _toEditModifiers(modifiers);

    if (intent is SelectIntent && intent.deferSelectionForDrag) {
      await dispatch(
        SetPendingSelect(
          elementId: intent.elementId,
          addToSelection: intent.addToSelection,
          pointerDownPosition: position,
        ),
      );
      return handled(message: 'Pending select');
    }

    final handledIntent = await _executeIntent(intent, position, editModifiers);
    return handledIntent ? handled(message: 'Selection handled') : unhandled();
  }

  Future<PluginResult> _handlePointerMove(PointerMoveInputEvent event) async {
    final pendingInfo = switch (state.application.interaction) {
      final PendingSelectState s => s.pendingSelect,
      _ => null,
    };
    if (pendingInfo != null) {
      final dx = event.position.x - pendingInfo.pointerDownPosition.x;
      final dy = event.position.y - pendingInfo.pointerDownPosition.y;
      final threshold = _dragStartThreshold;
      if ((dx * dx + dy * dy) >= (threshold * threshold)) {
        await dispatch(const ClearPendingSelect());

        if (state.domain.hasSelection) {
          final didStart = await _dispatchStartEditForIntent(
            intent: StartMoveIntent(
              elementId: pendingInfo.elementId,
              addToSelection: pendingInfo.addToSelection,
            ),
            position: pendingInfo.pointerDownPosition,
            modifiers: _toEditModifiers(event.modifiers),
          );
          if (didStart) {
            await _updateEditFromEvent(event);
          }
        }
      }

      return handled(message: 'Pending select drag');
    }

    final pendingMoveStart = switch (state.application.interaction) {
      final PendingMoveState s => s.pointerDownPosition,
      _ => null,
    };
    if (pendingMoveStart == null) {
      return unhandled();
    }

    final dx = event.position.x - pendingMoveStart.x;
    final dy = event.position.y - pendingMoveStart.y;
    final threshold = _dragStartThreshold;
    if ((dx * dx + dy * dy) >= (threshold * threshold)) {
      await dispatch(const ClearPendingMove());

      if (state.domain.hasSelection) {
        final selectedIds = state.domain.selection.selectedIds;
        final didStart = await _dispatchStartEditForIntent(
          intent: StartMoveIntent(
            elementId: selectedIds.first,
            addToSelection: false,
          ),
          position: pendingMoveStart,
          modifiers: _toEditModifiers(event.modifiers),
        );
        if (didStart) {
          await _updateEditFromEvent(event);
        }
      }
    }

    return handled(message: 'Pending move drag');
  }

  Future<PluginResult> _handlePointerUp(PointerUpInputEvent event) async {
    final pendingSelect = switch (state.application.interaction) {
      final PendingSelectState s => s.pendingSelect,
      _ => null,
    };
    if (pendingSelect == null) {
      if (state.application.interaction is! PendingMoveState) {
        return unhandled();
      }
      await dispatch(const ClearPendingMove());
      return handled(message: 'Pending move cleared');
    }

    await dispatch(
      SelectElement(
        elementId: pendingSelect.elementId,
        addToSelection: pendingSelect.addToSelection,
        position: pendingSelect.pointerDownPosition,
      ),
    );
    await dispatch(const ClearPendingSelect());
    return handled(message: 'Selection applied');
  }

  Future<PluginResult> _handlePointerCancel() async {
    if (state.application.interaction is PendingSelectState) {
      await dispatch(const ClearPendingSelect());
      return consumed(message: 'Pending select canceled');
    }
    if (state.application.interaction is PendingMoveState) {
      await dispatch(const ClearPendingMove());
      return consumed(message: 'Pending move canceled');
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
        await dispatch(SetPendingMove(pointerDownPosition: position));
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
      await dispatch(SetPendingMove(pointerDownPosition: position));
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
      modifiers: _toEditModifiers(event.modifiers),
    ),
  );

  EditModifiers _toEditModifiers(KeyModifiers modifiers) => EditModifiers(
    maintainAspectRatio: modifiers.shift,
    discreteAngle: modifiers.shift,
    fromCenter: modifiers.alt,
    snapOverride: modifiers.control,
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
    return element?.typeId == toolTypeId;
  }
}
