import '../../actions/draw_actions.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../services/draw_state_view_builder.dart';
import '../../utils/hit_test.dart';
import '../input_event.dart';
import '../plugin_core.dart';

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
      _routingPolicy.allowCreate(state);

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerDownInputEvent) {
      if (state.application.isCreating) {
        await dispatch(const FinishCreateElement());
        return handled(message: 'Create finished');
      }

      final toolTypeId = currentToolTypeId;
      if (toolTypeId == null) {
        return unhandled();
      }

      final document = state.domain.document;
      final tolerance = selectionConfig.interaction.handleTolerance;
      if (!state.domain.hasSelection &&
          !document.hasElementAtPoint(event.position, tolerance)) {
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

      final hitResult = hitTest.test(
        stateView: _stateView,
        position: event.position,
        config: selectionConfig,
        registry: drawContext.elementRegistry,
        tolerance: tolerance,
      );
      if (hitResult.isHandleHit) {
        return unhandled(reason: 'Selection handle hit');
      }
      if (hitResult.isHit) {
        // Only defer to selection if the hit element matches the current tool type
        if (hitResult.elementId != null && _isMatchingToolType(hitResult.elementId!)) {
          return unhandled();
        }
        // Otherwise, ignore the hit and proceed with creating a new element
      } else if (state.domain.hasSelection) {
        // If there's a selection and clicking on blank area, defer to selection plugin
        // to handle deselection instead of creating a new element
        return unhandled();
      }

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

    if (event is PointerMoveInputEvent) {
      if (!state.application.isCreating) {
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
      return handled(message: 'Create updated');
    }

    if (event is PointerUpInputEvent) {
      if (!state.application.isCreating) {
        return unhandled();
      }
      await dispatch(const FinishCreateElement());
      return handled(message: 'Create finished');
    }

    if (event is PointerCancelInputEvent) {
      if (!state.application.isCreating) {
        return unhandled();
      }
      await dispatch(const CancelCreateElement());
      return consumed(message: 'Create canceled');
    }

    return unhandled();
  }

  @override
  void reset() {
    currentToolTypeId = null;
  }

  DrawStateView get _stateView {
    final builder = _stateViewBuilder;
    if (builder == null) {
      throw StateError('CreatePlugin has not been loaded yet');
    }
    return builder.build(state);
  }

  /// Checks if the element with the given ID matches the current tool type.
  bool _isMatchingToolType(String elementId) {
    final toolTypeId = currentToolTypeId;
    if (toolTypeId == null) {
      return true; // No tool active, allow all
    }
    final element = state.domain.document.getElementById(elementId);
    return element?.typeId == toolTypeId;
  }
}
