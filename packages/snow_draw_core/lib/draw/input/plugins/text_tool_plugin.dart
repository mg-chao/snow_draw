import '../../actions/draw_actions.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../utils/hit_test.dart';
import '../input_event.dart';
import '../plugin_core.dart';

/// Plugin that handles text tool interactions.
class TextToolPlugin extends DrawInputPlugin {
  TextToolPlugin({
    required this.currentToolTypeId,
    InputRoutingPolicy? routingPolicy,
  }) : _routingPolicy = routingPolicy ?? InputRoutingPolicy.defaultPolicy,
       super(
         id: 'text_tool',
         name: 'Text Tool Plugin',
         priority: 5,
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

  bool get _isTextToolActive => currentToolTypeId == TextData.typeIdToken;

  bool get _isSelectionToolActive => currentToolTypeId == null;

  @override
  bool canHandle(InputEvent event, DrawState state) {
    if (state.application.interaction is TextEditingState) {
      return true;
    }
    if (_isTextToolActive) {
      return _routingPolicy.allowCreate(state);
    }
    if (_isSelectionToolActive) {
      return _routingPolicy.allowSelection(state);
    }
    return false;
  }

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    if (event is PointerDownInputEvent) {
      return _handlePointerDown(event);
    }
    if (event is PointerMoveInputEvent) {
      return _handlePointerMove();
    }
    if (event is PointerUpInputEvent) {
      return _handlePointerUp();
    }
    if (event is PointerCancelInputEvent) {
      return _handlePointerCancel();
    }
    return unhandled();
  }

  DrawStateView get _stateView {
    final builder = _stateViewBuilder;
    if (builder == null) {
      throw StateError('TextToolPlugin has not been loaded yet');
    }
    return builder.build(state);
  }

  Future<PluginResult> _handlePointerDown(PointerDownInputEvent event) async {
    final interaction = state.application.interaction;
    if (interaction is TextEditingState) {
      if (_isInsideEditingRect(interaction, event.position)) {
        return handled(message: 'Text editing focus retained');
      }

      if (_isSelectionBoxHit(interaction, event.position)) {
        await _finishTextEditForSelection(interaction, event.position);
        return unhandled(reason: 'Selection box hit during text edit');
      }

      await dispatch(
        FinishTextEdit(
          elementId: interaction.elementId,
          text: interaction.draftData.text,
          isNew: interaction.isNew,
        ),
      );

      if (_isTextToolActive) {
        final hitId = _hitTextElementId(event.position);
        if (hitId != null) {
          await dispatch(
            StartTextEdit(elementId: hitId, position: event.position),
          );
          return handled(message: 'Text edit restarted');
        }
      }

      return handled(message: 'Text edit finished');
    }

    if (_shouldDeferToSelectionBox(event.position)) {
      return unhandled(reason: 'Selection box hit');
    }

    if (_isTextToolActive) {
      final hitId = _hitTextElementId(event.position);

      // If there's a selection and we're clicking on a blank area (not hitting
      // any text element), defer to SelectPlugin to clear the selection instead
      // of creating a new text element.
      if (hitId == null && state.domain.hasSelection) {
        return unhandled(reason: 'Defer to selection clearing');
      }

      if (hitId != null && _hasMultipleSelectedTextElements()) {
        return unhandled(reason: 'Multiple text selection blocks editing');
      }

      await dispatch(StartTextEdit(elementId: hitId, position: event.position));
      return handled(message: 'Text edit started');
    }

    if (_shouldEnterEditFromSelection(event)) {
      final hitId = _hitTextElementId(
        event.position,
        allowedIds: state.domain.selection.selectedIds,
      );
      if (hitId != null) {
        await dispatch(
          StartTextEdit(elementId: hitId, position: event.position),
        );
        return handled(message: 'Text edit from selection');
      }
    }

    return unhandled();
  }

  Future<PluginResult> _handlePointerMove() async {
    if (state.application.interaction is TextEditingState) {
      return handled(message: 'Text editing pointer move ignored');
    }
    return unhandled();
  }

  Future<PluginResult> _handlePointerUp() async {
    if (state.application.interaction is TextEditingState) {
      return handled(message: 'Text editing pointer up ignored');
    }
    return unhandled();
  }

  Future<PluginResult> _handlePointerCancel() async {
    if (state.application.interaction is TextEditingState) {
      return handled(message: 'Text editing pointer cancel ignored');
    }
    return unhandled();
  }

  bool _isInsideEditingRect(TextEditingState interaction, DrawPoint position) =>
      _isInsideRect(interaction.rect, interaction.rotation, position);

  bool _isSelectionBoxHit(TextEditingState interaction, DrawPoint position) {
    if (!state.domain.selection.selectedIds.contains(interaction.elementId)) {
      return false;
    }

    final stateView = _stateView;
    if (!stateView.effectiveSelection.hasSelection) {
      return false;
    }

    final hitResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: drawContext.elementRegistry,
      filterTypeId: currentToolTypeId,
    );

    if (hitResult.isHandleHit) {
      return true;
    }

    return hitResult.isInSelectionPadding;
  }

  bool _shouldDeferToSelectionBox(DrawPoint position) {
    if (!state.domain.hasSelection) {
      return false;
    }

    if (!_hasSelectedTextElement()) {
      return false;
    }

    final stateView = _stateView;
    if (!stateView.effectiveSelection.hasSelection) {
      return false;
    }

    final hitResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: drawContext.elementRegistry,
      filterTypeId: currentToolTypeId,
    );

    final isSelectionHit =
        hitResult.isHandleHit || hitResult.isInSelectionPadding;

    if (!isSelectionHit) {
      return false;
    }

    return !_isInsideSelectedTextElement(position);
  }

  bool _hasSelectedTextElement() {
    for (final id in state.domain.selection.selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData) {
        return true;
      }
    }
    return false;
  }

  bool _hasMultipleSelectedTextElements() {
    var count = 0;
    for (final id in state.domain.selection.selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is TextData) {
        count += 1;
        if (count > 1) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isInsideSelectedTextElement(DrawPoint position) {
    for (final id in state.domain.selection.selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element?.data is! TextData) {
        continue;
      }
      if (_isInsideRect(element!.rect, element.rotation, position)) {
        return true;
      }
    }
    return false;
  }

  bool _isInsideRect(DrawRect rect, double rotation, DrawPoint position) {
    final local = rotation == 0
        ? position
        : ElementSpace(
            rotation: rotation,
            origin: rect.center,
          ).fromWorld(position);
    return local.x >= rect.minX &&
        local.x <= rect.maxX &&
        local.y >= rect.minY &&
        local.y <= rect.maxY;
  }

  Future<void> _finishTextEditForSelection(
    TextEditingState interaction,
    DrawPoint position,
  ) async {
    await dispatch(
      FinishTextEdit(
        elementId: interaction.elementId,
        text: interaction.draftData.text,
        isNew: interaction.isNew,
      ),
    );

    final trimmed = interaction.draftData.text.trim();
    if (!interaction.isNew && trimmed.isNotEmpty) {
      await dispatch(
        SelectElement(elementId: interaction.elementId, position: position),
      );
    }
  }

  bool _shouldEnterEditFromSelection(PointerDownInputEvent event) {
    if (_isTextToolActive) {
      return false;
    }
    if (!_isSelectionToolActive) {
      return false;
    }
    if (event.modifiers.shift) {
      return false;
    }
    if (!state.domain.hasSelection) {
      return false;
    }
    if (_hasMultipleSelectedTextElements()) {
      return false;
    }
    final hitId = _hitTextElementId(
      event.position,
      allowedIds: state.domain.selection.selectedIds,
    );
    return hitId != null;
  }

  String? _hitTextElementId(DrawPoint position, {Set<String>? allowedIds}) {
    final stateView = _stateView;
    final registry = drawContext.elementRegistry;
    final elements = stateView.elements;
    for (var i = elements.length - 1; i >= 0; i--) {
      final element = stateView.effectiveElement(elements[i]);
      if (allowedIds != null && !allowedIds.contains(element.id)) {
        continue;
      }
      if (element.data is! TextData) {
        continue;
      }
      final definition = registry.getDefinition(element.typeId);
      final hitTester = definition?.hitTester;
      final isHit =
          hitTester?.hitTest(element: element, position: position) ??
          _isInsideRect(element.rect, element.rotation, position);
      if (isHit) {
        return element.id;
      }
    }
    return null;
  }
}
