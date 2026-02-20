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

  final document = state.domain.document;
  final focusSerialId = targetIds.length == 1 ? targetIds.first : null;
  final textStyle = context.config.textStyle;
  final nextElements = <ElementState>[];
  var hasDocumentChanges = false;
  ElementState? focusTextElement;

  for (final element in document.elements) {
    final data = element.data;
    if (!targetIds.contains(element.id) || data is! SerialNumberData) {
      nextElements.add(element);
      continue;
    }

    final boundTextId = data.textElementId;
    final boundTextElement = boundTextId == null
        ? null
        : document.getElementById(boundTextId);
    if (boundTextElement != null && boundTextElement.data is TextData) {
      if (element.id == focusSerialId) {
        focusTextElement = boundTextElement;
      }
      nextElements.add(element);
      continue;
    }

    final textData = const TextData().withElementStyle(textStyle) as TextData;
    final textElement = ElementState(
      id: context.idGenerator(),
      rect: resolveSerialNumberBoundTextRect(
        serialElement: element,
        serialData: data,
        textData: textData,
      ),
      rotation: 0,
      opacity: textStyle.opacity,
      zIndex: element.zIndex + 1,
      data: textData,
    );
    nextElements
      ..add(
        element.copyWith(data: data.copyWith(textElementId: textElement.id)),
      )
      ..add(textElement);
    if (element.id == focusSerialId) {
      focusTextElement = textElement;
    }
    hasDocumentChanges = true;
  }

  if (!hasDocumentChanges && focusTextElement == null) {
    return state;
  }

  final nextState = hasDocumentChanges
      ? state.copyWith(
          domain: state.domain.copyWith(
            document: document.copyWith(elements: nextElements),
          ),
        )
      : state;

  if (hasDocumentChanges) {
    nextState.domain.document.warmCaches();
  }

  final focusedText = focusTextElement;
  if (focusedText == null) {
    return nextState;
  }

  final selectedState = applySelectionChange(nextState, {focusedText.id});
  final textData = focusedText.data as TextData;
  final textInteraction = TextEditingState(
    elementId: focusedText.id,
    draftData: textData,
    rect: focusedText.rect,
    isNew: false,
    opacity: focusedText.opacity,
    rotation: focusedText.rotation,
  );
  return selectedState.copyWith(
    application: selectedState.application.copyWith(
      interaction: textInteraction,
    ),
  );
}
