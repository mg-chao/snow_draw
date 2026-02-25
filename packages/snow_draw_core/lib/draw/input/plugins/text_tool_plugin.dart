import '../../actions/draw_actions.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/core/element_data.dart';
import '../../elements/core/element_type_id.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/draw_state_view.dart';
import '../../models/interaction_state.dart';
import '../../services/draw_state_view_builder.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../utils/hit_test.dart';
import '../input_event.dart';
import '../plugin_engine.dart';

/// Plugin that handles text tool interactions.
class TextToolPlugin extends DrawInputPlugin {
  TextToolPlugin({
    required this.currentToolTypeId,
    this.isSelectionToolActive = true,
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
  bool isSelectionToolActive;

  @override
  Future<void> onLoad(PluginContext context) async {
    await super.onLoad(context);
    _stateViewBuilder = DrawStateViewBuilder(
      editOperations: drawContext.editOperations,
    );
  }

  bool get _isTextToolActive => currentToolTypeId == TextData.typeIdToken;

  bool get _isSelectionToolModeActive =>
      currentToolTypeId == null && isSelectionToolActive;

  bool get _isSerialToolActive =>
      currentToolTypeId == SerialNumberData.typeIdToken;

  bool get _isSelectionLikeToolActive =>
      _isSelectionToolModeActive || _isSerialToolActive;

  @override
  bool canHandle(InputEvent _, DrawState state) {
    if (state.application.interaction is TextEditingState) {
      return true;
    }
    if (_isTextToolActive) {
      return _routingPolicy.allowCreate(state);
    }
    if (_isSelectionLikeToolActive) {
      return _routingPolicy.allowSelection(state);
    }
    return false;
  }

  @override
  Future<PluginResult> handleEvent(InputEvent event) => switch (event) {
    PointerDownInputEvent() => _handlePointerDown(event),
    PointerMoveInputEvent() => _ignoreWhileTextEditing(
      message: 'Text editing pointer move ignored',
    ),
    PointerUpInputEvent() => _ignoreWhileTextEditing(
      message: 'Text editing pointer up ignored',
    ),
    PointerCancelInputEvent() => _ignoreWhileTextEditing(
      message: 'Text editing pointer cancel ignored',
    ),
    _ => Future<PluginResult>.value(unhandled()),
  };

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
      return _handlePointerDownWhileEditing(
        interaction: interaction,
        position: event.position,
      );
    }

    if (_shouldDeferToSelectionBox(event.position)) {
      return unhandled(reason: 'Selection box hit');
    }

    if (_isTextToolActive) {
      return _handlePointerDownForTextTool(event.position);
    }

    final hitId = _selectedTextHitIdForEdit(event);
    if (hitId == null) {
      return unhandled();
    }

    await dispatch(StartTextEdit(elementId: hitId, position: event.position));
    return handled(message: 'Text edit from selection');
  }

  Future<PluginResult> _handlePointerDownWhileEditing({
    required TextEditingState interaction,
    required DrawPoint position,
  }) async {
    if (_isInsideRect(interaction.rect, interaction.rotation, position)) {
      return handled(message: 'Text editing focus retained');
    }

    if (_isSelectionBoxHit(interaction, position)) {
      await _finishTextEditForSelection(interaction, position);
      return unhandled(reason: 'Selection box hit during text edit');
    }

    await _finishTextEdit(interaction);

    if (!_isTextToolActive) {
      return handled(message: 'Text edit finished');
    }

    final hitId = _hitTextElementId(position);
    if (hitId == null) {
      return handled(message: 'Text edit finished');
    }

    await dispatch(StartTextEdit(elementId: hitId, position: position));
    return handled(message: 'Text edit restarted');
  }

  Future<PluginResult> _handlePointerDownForTextTool(DrawPoint position) async {
    final hitId = _hitTextElementId(position);

    if (hitId == null && state.domain.hasSelection) {
      return unhandled(reason: 'Defer to selection clearing');
    }

    if (hitId != null && _hasMultipleSelectedTextElements()) {
      return unhandled(reason: 'Multiple text selection blocks editing');
    }

    await dispatch(StartTextEdit(elementId: hitId, position: position));
    return handled(message: 'Text edit started');
  }

  Future<PluginResult> _ignoreWhileTextEditing({
    required String message,
  }) async {
    if (state.application.interaction is TextEditingState) {
      return handled(message: message);
    }
    return unhandled();
  }

  bool _isSelectionBoxHit(TextEditingState interaction, DrawPoint position) {
    if (!state.domain.selection.selectedIds.contains(interaction.elementId)) {
      return false;
    }

    return _isSelectionOverlayHit(position);
  }

  bool _isSelectionOverlayHit(DrawPoint position) {
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

    return hitResult.isHandleHit || hitResult.isInSelectionPadding;
  }

  bool _shouldDeferToSelectionBox(DrawPoint position) {
    if (!state.domain.hasSelection || !_hasSelectedTextElement()) {
      return false;
    }

    if (!_isSelectionOverlayHit(position)) {
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
    await _finishTextEdit(interaction);

    final trimmed = interaction.draftData.text.trim();
    if (!interaction.isNew && trimmed.isNotEmpty) {
      await dispatch(
        SelectElement(elementId: interaction.elementId, position: position),
      );
    }
  }

  Future<void> _finishTextEdit(TextEditingState interaction) => dispatch(
    FinishTextEdit(
      elementId: interaction.elementId,
      text: interaction.draftData.text,
      isNew: interaction.isNew,
    ),
  );

  String? _selectedTextHitIdForEdit(PointerDownInputEvent event) {
    if (!_isSelectionLikeToolActive) {
      return null;
    }
    if (event.modifiers.shift) {
      return null;
    }
    if (!state.domain.hasSelection) {
      return null;
    }
    if (_hasMultipleSelectedTextElements()) {
      return null;
    }
    return _hitTextElementId(
      event.position,
      allowedIds: state.domain.selection.selectedIds,
    );
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
