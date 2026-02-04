import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/types/serial_number/serial_number_binding.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../core/reducer_utils.dart';

DrawState handleCreateSerialNumberTextElements(
  DrawState state,
  CreateSerialNumberTextElements action,
  ElementReducerDeps context,
) {
  final targetIds = action.elementIds.toSet();
  if (targetIds.isEmpty) {
    return state;
  }

  final isSingleTarget = action.elementIds.length == 1;
  final singleTargetId = isSingleTarget ? action.elementIds.first : null;
  final textStyle = context.config.textStyle;
  final elements = <ElementState>[];
  var didChange = false;
  String? focusTextId;

  for (final element in state.domain.document.elements) {
    if (!targetIds.contains(element.id)) {
      elements.add(element);
      continue;
    }

    final data = element.data;
    if (data is! SerialNumberData) {
      elements.add(element);
      continue;
    }

    final boundId = data.textElementId;
    final boundElement = boundId == null
        ? null
        : state.domain.document.getElementById(boundId);
    if (boundElement != null && boundElement.data is TextData) {
      if (isSingleTarget && element.id == singleTargetId) {
        focusTextId = boundId;
      }
      elements.add(element);
      continue;
    }

    final textId = context.idGenerator();
    final textData = const TextData().withElementStyle(textStyle) as TextData;
    final textRect = resolveSerialNumberBoundTextRect(
      serialElement: element,
      serialData: data,
      textData: textData,
    );
    final textElement = ElementState(
      id: textId,
      rect: textRect,
      rotation: 0,
      opacity: textStyle.opacity,
      zIndex: element.zIndex + 1,
      data: textData,
    );
    final updatedSerial = element.copyWith(
      data: data.copyWith(textElementId: textId),
    );
    elements
      ..add(updatedSerial)
      ..add(textElement);
    if (isSingleTarget && element.id == singleTargetId) {
      focusTextId = textId;
    }
    didChange = true;
  }

  if (!didChange && focusTextId == null) {
    return state;
  }

  final nextState = didChange
      ? state.copyWith(
          domain: state.domain.copyWith(
            document: state.domain.document.copyWith(elements: elements),
          ),
        )
      : state;

  if (didChange) {
    nextState.domain.document.warmCaches();
  }

  if (focusTextId == null) {
    return nextState;
  }

  final textElement = nextState.domain.document.getElementById(focusTextId);
  if (textElement == null || textElement.data is! TextData) {
    return nextState;
  }

  final selectedState = applySelectionChange(nextState, {focusTextId});
  final textData = textElement.data as TextData;
  final textInteraction = TextEditingState(
    elementId: focusTextId,
    draftData: textData,
    rect: textElement.rect,
    isNew: false,
    opacity: textElement.opacity,
    rotation: textElement.rotation,
  );
  return selectedState.copyWith(
    application: selectedState.application.copyWith(
      interaction: textInteraction,
    ),
  );
}
