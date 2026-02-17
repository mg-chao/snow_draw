import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/elements/core/element_data.dart';
import '../../draw/elements/core/element_type_id.dart';
import '../../draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/models/interaction_state.dart';

/// Policy object for pointer-move dispatch behavior on the canvas.
///
/// High-frequency interactions are frame-coalesced by default to keep expensive
/// operations responsive. Lightweight interactions (line point drags, serial
/// low-latency sessions) bypass coalescing so they can consume raw pointer
/// updates and reach the display refresh limit.
class PointerMoveDispatchPolicy {
  const PointerMoveDispatchPolicy._();

  /// Returns true when pointer moves should be frame-coalesced.
  static bool shouldCoalesce({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
    bool isLowLatencySerialInteraction = false,
  }) {
    if (_isLowLatencyLineInteraction(interaction) ||
        isLowLatencySerialInteraction) {
      return false;
    }

    if (_isFreeDrawLineConstraint(interaction)) {
      return true;
    }

    if (shouldBatchFreeDrawSamples(
      interaction: interaction,
      currentToolTypeId: currentToolTypeId,
      isShiftPressed: isShiftPressed,
    )) {
      return true;
    }

    if (interaction is CreatingState) {
      return interaction.creationMode is! FreeDrawCreationMode;
    }

    return interaction is EditingState ||
        interaction is BoxSelectingState ||
        interaction is DragPendingState;
  }

  /// Returns true when free-draw samples should be merged into batched updates.
  static bool shouldBatchFreeDrawSamples({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
  }) {
    if (isShiftPressed) {
      return false;
    }
    if (currentToolTypeId == FreeDrawData.typeIdToken) {
      return true;
    }
    return interaction is CreatingState &&
        interaction.elementData is FreeDrawData;
  }

  static bool _isLowLatencyLineInteraction(InteractionState interaction) {
    if (interaction is CreatingState) {
      return interaction.elementData is LineData;
    }
    if (interaction is EditingState &&
        interaction.context is ArrowPointEditContext) {
      final context = interaction.context as ArrowPointEditContext;
      return context.isLineElement;
    }
    return false;
  }

  static bool _isFreeDrawLineConstraint(InteractionState interaction) {
    if (interaction is! CreatingState ||
        interaction.creationMode is! FreeDrawCreationMode) {
      return false;
    }
    final mode = interaction.creationMode as FreeDrawCreationMode;
    return mode.isLineActive;
  }
}
