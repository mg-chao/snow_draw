import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/interaction_state.dart';

/// Resolves serial-number specific interaction categories.
class SerialNumberInteractionClassifier {
  const SerialNumberInteractionClassifier._();

  /// Returns true when [interaction] is creating a serial-number element.
  static bool isSerialNumberCreation(InteractionState interaction) =>
      interaction is CreatingState &&
      interaction.elementData is SerialNumberData;

  /// Returns true when [interaction] edits a single serial-number element.
  static bool isSingleSerialNumberEdit({
    required InteractionState interaction,
    required DocumentState document,
  }) {
    if (interaction is! EditingState ||
        interaction.context.selectedIdsAtStart.length != 1) {
      return false;
    }

    return document
            .getElementById(interaction.context.selectedIdsAtStart.first)
            ?.data
        is SerialNumberData;
  }

  /// Returns true when pointer moves should prioritize serial latency.
  static bool isLowLatencySerialInteraction({
    required InteractionState interaction,
    required DocumentState document,
  }) =>
      isSerialNumberCreation(interaction) ||
      isSingleSerialNumberEdit(interaction: interaction, document: document);
}
