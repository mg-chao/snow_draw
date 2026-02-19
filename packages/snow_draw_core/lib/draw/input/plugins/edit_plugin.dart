import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';
import '../../types/draw_point.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that manages edit sessions (move/resize/rotate).
class EditPlugin extends DrawInputPlugin {
  EditPlugin({InputRoutingPolicy? routingPolicy})
    : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
      super(
        id: 'edit',
        name: 'Edit Plugin',
        priority: 0,
        supportedEventTypes: {
          PointerDownInputEvent,
          PointerMoveInputEvent,
          PointerUpInputEvent,
          PointerCancelInputEvent,
        },
      );
  final InputRoutingPolicy _routingPolicy;
  DrawPoint? _lastUpdatePosition;
  KeyModifiers? _lastUpdateModifiers;

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      state.application.isEditing;

  @override
  void reset() {
    _clearUpdateSignature();
  }

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerDownInputEvent) {
      _clearUpdateSignature();
      switch (_routingPolicy.editPointerDownBehavior) {
        case EditPointerDownBehavior.ignore:
          return unhandled();
        case EditPointerDownBehavior.cancelEdit:
          await dispatch(const CancelEdit());
          return handled(message: 'Edit canceled');
        case EditPointerDownBehavior.commitEdit:
          await dispatch(const FinishEdit());
          return handled(message: 'Edit committed');
      }
    }

    if (event is PointerMoveInputEvent) {
      if (!_shouldDispatchUpdate(event.position, event.modifiers)) {
        return handled(message: 'Edit unchanged');
      }
      await dispatch(
        UpdateEdit(
          currentPosition: event.position,
          modifiers: event.modifiers.toEditModifiers(),
        ),
      );
      return handled(message: 'Edit updated');
    }

    if (event is PointerUpInputEvent) {
      _clearUpdateSignature();
      await dispatch(const FinishEdit());
      return handled(message: 'Edit finished');
    }

    if (event is PointerCancelInputEvent) {
      _clearUpdateSignature();
      await dispatch(const CancelEdit());
      return consumed(message: 'Edit canceled');
    }

    return unhandled();
  }

  bool _shouldDispatchUpdate(DrawPoint position, KeyModifiers modifiers) {
    if (_positionsMatchForDedup(
          previous: _lastUpdatePosition,
          next: position,
        ) &&
        _lastUpdateModifiers == modifiers) {
      return false;
    }
    _lastUpdatePosition = position;
    _lastUpdateModifiers = modifiers;
    return true;
  }

  bool _positionsMatchForDedup({
    required DrawPoint? previous,
    required DrawPoint next,
  }) => previous != null && previous.x == next.x && previous.y == next.y;

  void _clearUpdateSignature() {
    _lastUpdatePosition = null;
    _lastUpdateModifiers = null;
  }
}
