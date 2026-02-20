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
  bool canHandle(InputEvent _, DrawState state) => state.application.isEditing;

  @override
  void reset() => _clearUpdateSignature();

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    switch (event) {
      case PointerDownInputEvent():
        return _handlePointerDown();
      case PointerMoveInputEvent(:final position, :final modifiers):
        return _handlePointerMove(position: position, modifiers: modifiers);
      case PointerUpInputEvent():
        return _handlePointerUp();
      case PointerCancelInputEvent():
        return _handlePointerCancel();
      default:
        return unhandled();
    }
  }

  Future<PluginResult> _handlePointerDown() async {
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

  Future<PluginResult> _handlePointerMove({
    required DrawPoint position,
    required KeyModifiers modifiers,
  }) async {
    if (!_shouldDispatchUpdate(position, modifiers)) {
      return handled(message: 'Edit unchanged');
    }

    await dispatch(
      UpdateEdit(
        currentPosition: position,
        modifiers: modifiers.toEditModifiers(),
      ),
    );
    return handled(message: 'Edit updated');
  }

  Future<PluginResult> _handlePointerUp() async {
    _clearUpdateSignature();
    await dispatch(const FinishEdit());
    return handled(message: 'Edit finished');
  }

  Future<PluginResult> _handlePointerCancel() async {
    _clearUpdateSignature();
    await dispatch(const CancelEdit());
    return consumed(message: 'Edit canceled');
  }

  bool _shouldDispatchUpdate(DrawPoint position, KeyModifiers modifiers) {
    final previous = _lastUpdatePosition;
    if (previous != null &&
        previous.x == position.x &&
        previous.y == position.y &&
        _lastUpdateModifiers == modifiers) {
      return false;
    }

    _lastUpdatePosition = position;
    _lastUpdateModifiers = modifiers;
    return true;
  }

  void _clearUpdateSignature() {
    _lastUpdatePosition = null;
    _lastUpdateModifiers = null;
  }
}
