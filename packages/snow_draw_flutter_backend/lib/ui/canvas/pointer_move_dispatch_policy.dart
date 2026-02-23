import 'package:snow_draw_core/snow_draw_core.dart';

/// Policy object for pointer-move dispatch behavior on the canvas.
///
/// Pointer devices can produce events at 125-1000 Hz, which can overwhelm
/// store dispatch even for lightweight interactions. The policy therefore
/// defaults to frame-aligned coalescing and only preserves full sample streams
/// for free-draw sessions that explicitly consume batched points.
class PointerMoveDispatchPolicy {
  const PointerMoveDispatchPolicy._();

  /// Returns true when pointer moves should be frame-coalesced.
  static bool shouldCoalesce({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
    bool isLowLatencySerialInteraction = false,
  }) =>
      shouldBatchFreeDrawSamples(
        interaction: interaction,
        currentToolTypeId: currentToolTypeId,
        isShiftPressed: isShiftPressed,
      ) ||
      isLowLatencySerialInteraction ||
      interaction is CreatingState ||
      interaction is EditingState ||
      interaction is BoxSelectingState ||
      interaction is DragPendingState;

  /// Returns true when free-draw samples should be merged into batched updates.
  static bool shouldBatchFreeDrawSamples({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
  }) =>
      !isShiftPressed &&
      (currentToolTypeId == FreeDrawData.typeIdToken ||
          interaction is CreatingState &&
              interaction.elementData is FreeDrawData);
}
