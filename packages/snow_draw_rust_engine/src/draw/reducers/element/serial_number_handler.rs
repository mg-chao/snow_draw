#![allow(dead_code)]

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::Arc;

use crate::draw::config::draw_config::ElementStyleConfig;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::types::serial_number::serial_number_binding;
use crate::draw::elements::types::serial_number::serial_number_data::{
    SerialNumberData, SerialNumberDataPatch,
};
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::interaction_state::{InteractionState, TextEditingState};

/// Action payload for creating bound text elements for serial-number elements.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CreateSerialNumberTextElements {
    pub element_ids: Vec<String>,
}

impl CreateSerialNumberTextElements {
    pub fn new(element_ids: Vec<String>) -> Self {
        Self { element_ids }
    }
}

/// Adapter trait for the state shape consumed by
/// [`handle_create_serial_number_text_elements`].
///
/// This keeps reducer behavior reusable across state models while retaining the
/// same serial-number/text binding workflow.
pub trait SerialNumberTextReducerState: Clone {
    fn document_elements(&self) -> &[ElementState];

    fn with_document_elements(&self, elements: Vec<ElementState>) -> Self;

    fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self;

    fn with_interaction(&self, interaction: InteractionState) -> Self;

    fn warm_document_caches(&self) {}
}

/// Creates missing bound text elements for the provided serial-number ids.
///
/// Mirrors the Dart reducer behavior:
/// - No-op when `action.element_ids` is empty.
/// - Reuses existing valid bound text elements.
/// - Creates text elements when bindings are missing or invalid.
/// - Focuses the bound text element when exactly one serial-number id is
///   targeted and enters text-editing interaction for that element.
pub fn handle_create_serial_number_text_elements<S>(
    state: &S,
    action: &CreateSerialNumberTextElements,
    context: &DrawContext,
) -> S
where
    S: SerialNumberTextReducerState,
{
    let target_ids = action
        .element_ids
        .iter()
        .map(|id| id.as_str())
        .collect::<HashSet<_>>();
    if target_ids.is_empty() {
        return state.clone();
    }

    let focus_serial_id = if target_ids.len() == 1 {
        target_ids.iter().next().copied()
    } else {
        None
    };

    let draw_config = context.config();
    let text_style = draw_config.text_style;
    let base_text_data = build_styled_text_data(&text_style);

    let document_elements = state.document_elements();
    let elements_by_id = document_elements
        .iter()
        .map(|element| (element.id.as_str(), element))
        .collect::<HashMap<_, _>>();

    let mut next_elements = Vec::with_capacity(document_elements.len() + target_ids.len());
    let mut has_document_changes = false;
    let mut focus_text_element = None::<ElementState>;

    for element in document_elements {
        if !target_ids.contains(element.id.as_str()) {
            next_elements.push(element.clone());
            continue;
        }

        let Some(serial_data) = decode_serial_number_data(element.data.as_ref()) else {
            next_elements.push(element.clone());
            continue;
        };

        let bound_text_element = serial_data
            .text_element_id
            .as_deref()
            .and_then(|id| elements_by_id.get(id).copied());

        if let Some(bound_text_element) = bound_text_element {
            if decode_text_data(bound_text_element.data.as_ref()).is_some() {
                if Some(element.id.as_str()) == focus_serial_id {
                    focus_text_element = Some(bound_text_element.clone());
                }
                next_elements.push(element.clone());
                continue;
            }
        }

        let text_data = base_text_data.clone();
        let text_element = ElementState::new(
            context.next_id(),
            resolve_bound_text_rect(element, &serial_data, &text_data),
            0.0,
            text_style.opacity,
            element.z_index + 1,
            Arc::new(text_data),
        );

        let updated_serial_data = serial_data.copy_with(SerialNumberDataPatch {
            text_element_id: Some(Some(text_element.id.clone())),
            ..SerialNumberDataPatch::default()
        });
        let updated_serial_element = element.copy_with(
            None,
            None,
            None,
            None,
            None,
            Some(Arc::new(updated_serial_data)),
        );

        next_elements.push(updated_serial_element);
        next_elements.push(text_element.clone());

        if Some(element.id.as_str()) == focus_serial_id {
            focus_text_element = Some(text_element);
        }
        has_document_changes = true;
    }

    if !has_document_changes && focus_text_element.is_none() {
        return state.clone();
    }

    let next_state = if has_document_changes {
        state.with_document_elements(next_elements)
    } else {
        state.clone()
    };

    if has_document_changes {
        next_state.warm_document_caches();
    }

    let Some(focused_text) = focus_text_element else {
        return next_state;
    };

    let mut selected_ids = BTreeSet::new();
    selected_ids.insert(focused_text.id.clone());

    let selected_state = next_state.apply_selection_change(selected_ids);

    let Some(text_data) = decode_text_data(focused_text.data.as_ref()) else {
        return selected_state;
    };

    let text_interaction = TextEditingState::new(
        focused_text.id,
        text_data,
        focused_text.rect,
        false,
        focused_text.opacity,
        focused_text.rotation,
        None,
    );

    selected_state.with_interaction(InteractionState::TextEditing(text_interaction))
}

fn build_styled_text_data(text_style: &ElementStyleConfig) -> TextData {
    let styled = TextData::default().with_element_style(text_style.clone());
    TextData::from_json(&styled.to_json()).unwrap_or_default()
}

fn resolve_bound_text_rect(
    serial_element: &ElementState,
    serial_data: &SerialNumberData,
    text_data: &TextData,
) -> crate::draw::types::draw_rect::DrawRect {
    serial_number_binding::resolve_serial_number_bound_text_rect(
        serial_element,
        serial_data,
        text_data,
        None,
        None,
    )
}

fn decode_text_data(data: &dyn ElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn ElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

#[cfg(test)]
mod tests {
    use super::{
        handle_create_serial_number_text_elements, CreateSerialNumberTextElements,
        SerialNumberTextReducerState,
    };
    use std::collections::{BTreeSet, VecDeque};
    use std::sync::{Arc, Mutex};

    use crate::draw::core::draw_context::DrawContext;
    use crate::draw::elements::types::serial_number::serial_number_data::{
        SerialNumberData, SerialNumberDataPatch,
    };
    use crate::draw::elements::types::text::text_data::TextData;
    use crate::draw::models::element_state::ElementState;
    use crate::draw::models::interaction_state::{IdleState, InteractionState};
    use crate::draw::types::draw_rect::DrawRect;
    use crate::utils::id_generator::IdGenerator;

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        elements: Vec<ElementState>,
        selected_ids: BTreeSet<String>,
        interaction: InteractionState,
    }

    impl TestState {
        fn new(elements: Vec<ElementState>) -> Self {
            Self {
                elements,
                selected_ids: BTreeSet::new(),
                interaction: InteractionState::Idle(IdleState),
            }
        }
    }

    impl SerialNumberTextReducerState for TestState {
        fn document_elements(&self) -> &[ElementState] {
            &self.elements
        }

        fn with_document_elements(&self, elements: Vec<ElementState>) -> Self {
            Self {
                elements,
                ..self.clone()
            }
        }

        fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self {
            Self {
                selected_ids,
                ..self.clone()
            }
        }

        fn with_interaction(&self, interaction: InteractionState) -> Self {
            Self {
                interaction,
                ..self.clone()
            }
        }
    }

    fn serial_element(id: &str, bound_text_id: Option<&str>, z_index: i64) -> ElementState {
        let serial_data = SerialNumberData::default().copy_with(SerialNumberDataPatch {
            text_element_id: Some(bound_text_id.map(str::to_owned)),
            ..SerialNumberDataPatch::default()
        });

        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            z_index,
            Arc::new(serial_data),
        )
    }

    fn text_element(id: &str, z_index: i64) -> ElementState {
        ElementState::new(
            id,
            DrawRect::new(38.0, 0.0, 120.0, 24.0),
            0.0,
            1.0,
            z_index,
            Arc::new(TextData::default()),
        )
    }

    fn context_with_ids(ids: &[&str]) -> DrawContext {
        let queue = Arc::new(Mutex::new(
            ids.iter()
                .map(|id| (*id).to_owned())
                .collect::<VecDeque<_>>(),
        ));
        let generator: IdGenerator = {
            let queue = queue.clone();
            Arc::new(move || {
                queue
                    .lock()
                    .expect("id queue mutex poisoned")
                    .pop_front()
                    .unwrap_or_else(|| "fallback-id".to_owned())
            })
        };

        DrawContext::with_defaults(None, None, Some(generator), None, None, None, None, None)
    }

    #[test]
    fn creates_bound_text_element_for_target_serial_number() {
        let state = TestState::new(vec![serial_element("serial-1", None, 2)]);
        let action = CreateSerialNumberTextElements::new(vec!["serial-1".to_owned()]);
        let context = context_with_ids(&["text-1"]);

        let next = handle_create_serial_number_text_elements(&state, &action, &context);

        assert_eq!(next.elements.len(), 2);

        let updated_serial_data = SerialNumberData::from_json(&next.elements[0].data.to_json())
            .expect("serial data should decode");
        assert_eq!(
            updated_serial_data.text_element_id.as_deref(),
            Some("text-1")
        );

        assert_eq!(next.elements[1].id, "text-1");
        assert_eq!(next.elements[1].z_index, 3);
        assert!(TextData::from_json(&next.elements[1].data.to_json()).is_ok());

        assert_eq!(
            next.selected_ids,
            ["text-1".to_owned()].into_iter().collect::<BTreeSet<_>>()
        );

        match &next.interaction {
            InteractionState::TextEditing(editing) => {
                assert_eq!(editing.element_id, "text-1");
                assert!(!editing.is_new);
            }
            other => panic!("expected text-editing interaction, got {other:?}"),
        }
    }

    #[test]
    fn reuses_existing_bound_text_element_and_enters_text_editing() {
        let state = TestState::new(vec![
            serial_element("serial-1", Some("text-1"), 2),
            text_element("text-1", 3),
        ]);
        let action = CreateSerialNumberTextElements::new(vec!["serial-1".to_owned()]);
        let context = context_with_ids(&["unused-id"]);

        let next = handle_create_serial_number_text_elements(&state, &action, &context);

        assert_eq!(next.elements, state.elements);
        assert_eq!(
            next.selected_ids,
            ["text-1".to_owned()].into_iter().collect::<BTreeSet<_>>()
        );
        assert!(matches!(next.interaction, InteractionState::TextEditing(_)));
    }

    #[test]
    fn empty_target_list_is_noop() {
        let state = TestState::new(vec![serial_element("serial-1", None, 0)]);
        let action = CreateSerialNumberTextElements::default();
        let context = context_with_ids(&["text-1"]);

        let next = handle_create_serial_number_text_elements(&state, &action, &context);

        assert_eq!(next, state);
    }
}
