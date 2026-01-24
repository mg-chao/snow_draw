import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that updates box selection interactions.
class BoxSelectPlugin extends DrawInputPlugin {
  BoxSelectPlugin({InputRoutingPolicy? routingPolicy})
    : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
      super(
        id: 'box_select',
        name: 'Box Select Plugin',
        priority: 30,
        supportedEventTypes: {
          PointerMoveInputEvent,
          PointerUpInputEvent,
          PointerCancelInputEvent,
        },
      );
  final InputRoutingPolicy _routingPolicy;

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      _routingPolicy.allowBoxSelect(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerMoveInputEvent) {
      if (!state.application.isBoxSelecting) {
        return unhandled();
      }
      await dispatch(UpdateBoxSelect(currentPosition: event.position));
      return handled(message: 'Box select updated');
    }

    if (event is PointerUpInputEvent) {
      if (!state.application.isBoxSelecting) {
        return unhandled();
      }
      await dispatch(const FinishBoxSelect());
      return handled(message: 'Box select finished');
    }

    if (event is PointerCancelInputEvent) {
      if (!state.application.isBoxSelecting) {
        return unhandled();
      }
      await dispatch(const CancelBoxSelect());
      return consumed(message: 'Box select canceled');
    }

    return unhandled();
  }
}
