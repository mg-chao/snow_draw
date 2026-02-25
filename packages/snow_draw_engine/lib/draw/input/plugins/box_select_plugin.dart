import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';
import '../input_event.dart';
import '../plugin_engine.dart';

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
    if (!state.application.isBoxSelecting) {
      return unhandled();
    }

    switch (event) {
      case PointerMoveInputEvent(:final position):
        await dispatch(UpdateBoxSelect(currentPosition: position));
        return handled(message: 'Box select updated');
      case PointerUpInputEvent():
        await dispatch(const FinishBoxSelect());
        return handled(message: 'Box select finished');
      case PointerCancelInputEvent():
        await dispatch(const CancelBoxSelect());
        return consumed(message: 'Box select canceled');
      default:
        return unhandled();
    }
  }
}
