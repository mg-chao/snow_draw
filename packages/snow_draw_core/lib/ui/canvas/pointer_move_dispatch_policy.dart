import '../../draw/elements/core/element_data.dart';
import '../../draw/elements/core/element_type_id.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/models/interaction_state.dart';

/// Dispatch strategy for pointer-move events.
///
/// - [immediate]: dispatch every event in order.
/// - [frameLatest]: coalesce to one latest event per frame.
/// - [frameBatchedSamples]: coalesce to one event per frame while preserving
///   intermediate samples for reducers that can process batched points.
enum PointerMoveDispatchMode { immediate, frameLatest, frameBatchedSamples }

/// Resolved plan describing how pointer moves should be dispatched.
class PointerMoveDispatchPlan {
  const PointerMoveDispatchPlan(this.mode);

  final PointerMoveDispatchMode mode;

  bool get shouldCoalesce => mode != PointerMoveDispatchMode.immediate;

  bool get shouldBatchSamples =>
      mode == PointerMoveDispatchMode.frameBatchedSamples;
}

/// Policy object for pointer-move dispatch behavior on the canvas.
///
/// Pointer devices can produce events at 125-1000 Hz, which can overwhelm
/// store dispatch even for lightweight interactions. The policy therefore
/// defaults to frame-aligned coalescing and only preserves full sample streams
/// for free-draw sessions that explicitly consume batched points.
class PointerMoveDispatchPolicy {
  const PointerMoveDispatchPolicy._();

  /// Resolves the pointer-move dispatch plan for the current interaction.
  static PointerMoveDispatchPlan resolvePlan({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
    bool isLowLatencySerialInteraction = false,
  }) {
    if (shouldBatchFreeDrawSamples(
      interaction: interaction,
      currentToolTypeId: currentToolTypeId,
      isShiftPressed: isShiftPressed,
    )) {
      return const PointerMoveDispatchPlan(
        PointerMoveDispatchMode.frameBatchedSamples,
      );
    }

    if (isLowLatencySerialInteraction ||
        interaction is CreatingState ||
        interaction is EditingState ||
        interaction is BoxSelectingState ||
        interaction is DragPendingState) {
      return const PointerMoveDispatchPlan(PointerMoveDispatchMode.frameLatest);
    }

    return const PointerMoveDispatchPlan(PointerMoveDispatchMode.immediate);
  }

  /// Returns true when pointer moves should be frame-coalesced.
  static bool shouldCoalesce({
    required InteractionState interaction,
    required ElementTypeId<ElementData>? currentToolTypeId,
    required bool isShiftPressed,
    bool isLowLatencySerialInteraction = false,
  }) => resolvePlan(
    interaction: interaction,
    currentToolTypeId: currentToolTypeId,
    isShiftPressed: isShiftPressed,
    isLowLatencySerialInteraction: isLowLatencySerialInteraction,
  ).shouldCoalesce;

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
