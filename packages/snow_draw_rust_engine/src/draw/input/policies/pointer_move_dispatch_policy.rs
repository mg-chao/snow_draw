#![allow(dead_code)]

use crate::draw::elements::core::element_data::{DynElementData, ElementTypeId};
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::models::interaction_state::InteractionState;

/// Policy object for pointer-move dispatch behavior on the canvas.
///
/// Pointer devices can produce events at very high frequencies, which can
/// overwhelm store dispatch even for lightweight interactions. The policy
/// therefore defaults to frame-aligned coalescing and only preserves full
/// sample streams for free-draw sessions that consume batched points.
pub struct PointerMoveDispatchPolicy;

impl PointerMoveDispatchPolicy {
    /// Returns true when pointer moves should be frame-coalesced.
    pub fn should_coalesce(
        interaction: &InteractionState,
        current_tool_type_id: Option<&ElementTypeId<DynElementData>>,
        is_shift_pressed: bool,
        is_low_latency_serial_interaction: bool,
    ) -> bool {
        Self::should_batch_free_draw_samples(interaction, current_tool_type_id, is_shift_pressed)
            || is_low_latency_serial_interaction
            || matches!(
                interaction,
                InteractionState::Creating(_)
                    | InteractionState::Editing(_)
                    | InteractionState::BoxSelecting(_)
                    | InteractionState::DragPending(_)
            )
    }

    /// Returns true when free-draw samples should be merged into batched
    /// updates.
    pub fn should_batch_free_draw_samples(
        interaction: &InteractionState,
        current_tool_type_id: Option<&ElementTypeId<DynElementData>>,
        is_shift_pressed: bool,
    ) -> bool {
        if is_shift_pressed {
            return false;
        }

        let is_free_draw_tool = current_tool_type_id
            .map(|type_id| type_id.as_str() == FreeDrawData::TYPE_ID_TOKEN)
            .unwrap_or(false);

        let is_creating_free_draw = match interaction {
            InteractionState::Creating(creating) => {
                creating.element_data().type_id().as_str() == FreeDrawData::TYPE_ID_TOKEN
            }
            _ => false,
        };

        is_free_draw_tool || is_creating_free_draw
    }
}
