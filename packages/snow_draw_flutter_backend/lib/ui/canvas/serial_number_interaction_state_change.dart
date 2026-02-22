import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';
import 'serial_number_interaction_classifier.dart';

/// Returns true when only an in-progress serial-number interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can skip cursor hit-testing work while still repainting previews.
bool isSerialNumberInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: SerialNumberInteractionClassifier.isSerialNumberCreation,
  supportsEditing: (interaction, document) =>
      SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: interaction,
        document: document,
      ),
);
