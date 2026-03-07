#![allow(dead_code)]

use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::models::document_state::{DocumentState, ElementData as DocumentElementData};
use crate::draw::models::interaction_state::InteractionState;

/// Utility classifier for serial-number specific interaction fast paths.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SerialNumberInteractionClassifier;

impl SerialNumberInteractionClassifier {
    /// Returns `true` when current interaction is creating a serial-number element.
    pub fn is_serial_number_creation(interaction: &InteractionState) -> bool {
        let InteractionState::Creating(creating) = interaction else {
            return false;
        };

        creating.element_data().type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN
    }

    /// Returns `true` when current interaction edits a single serial-number element.
    pub fn is_single_serial_number_edit(
        interaction: &InteractionState,
        document: &DocumentState,
    ) -> bool {
        let InteractionState::Editing(editing) = interaction else {
            return false;
        };

        if editing.context.selected_ids_at_start.len() != 1 {
            return false;
        }

        let Some(element_id) = editing.context.selected_ids_at_start.iter().next() else {
            return false;
        };

        matches!(
            document
                .get_element_by_id(element_id)
                .map(|element| &element.data),
            Some(DocumentElementData::SerialNumber(_))
        )
    }

    /// Returns `true` when pointer updates should prioritize serial interaction latency.
    pub fn is_low_latency_serial_interaction(
        interaction: &InteractionState,
        document: &DocumentState,
    ) -> bool {
        Self::is_serial_number_creation(interaction)
            || Self::is_single_serial_number_edit(interaction, document)
    }
}
