import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';
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

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      state.application.isEditing;

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerDownInputEvent) {
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
      await dispatch(
        UpdateEdit(
          currentPosition: event.position,
          modifiers: event.modifiers.toEditModifiers(),
        ),
      );
      return handled(message: 'Edit updated');
    }

    if (event is PointerUpInputEvent) {
      await dispatch(const FinishEdit());
      return handled(message: 'Edit finished');
    }

    if (event is PointerCancelInputEvent) {
      await dispatch(const CancelEdit());
      return consumed(message: 'Edit canceled');
    }

    return unhandled();
  }
}
