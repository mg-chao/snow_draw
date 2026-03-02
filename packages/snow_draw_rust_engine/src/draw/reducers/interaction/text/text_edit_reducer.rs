#![allow(dead_code)]

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use crate::draw::config::draw_config::ElementStyleConfig;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowData, ArrowDataPatch, NullableField as ArrowNullableField,
};
use crate::draw::elements::types::serial_number::serial_number_data::{
    SerialNumberData, SerialNumberDataPatch,
};
use crate::draw::elements::types::text::text_data::{TextData, TextDataPatch};
use crate::draw::elements::types::text::text_editing_geometry::{
    resolve_initial_text_editing_rect, resolve_text_editing_rect, TextData as GeometryTextData,
    TextMetricsService as GeometryTextMetricsService,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::interaction_state::TextEditingState;
use crate::draw::reducers::core::reducer_utils::resolve_next_z_index;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Action payload for entering text-editing mode.
#[derive(Clone, Debug, PartialEq)]
pub struct StartTextEdit {
    pub element_id: Option<String>,
    pub position: DrawPoint,
}

impl StartTextEdit {
    pub fn new(element_id: Option<String>, position: DrawPoint) -> Self {
        Self {
            element_id,
            position,
        }
    }
}

/// Action payload for updating in-progress text-editing draft state.
#[derive(Clone, Debug, PartialEq)]
pub struct UpdateTextEdit {
    pub text: String,
    pub rect: Option<DrawRect>,
}

impl UpdateTextEdit {
    pub fn new(text: impl Into<String>, rect: Option<DrawRect>) -> Self {
        Self {
            text: text.into(),
            rect,
        }
    }
}

/// Action payload for finishing text editing and committing/discarding draft.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FinishTextEdit {
    pub text: String,
}

impl FinishTextEdit {
    pub fn new(text: impl Into<String>) -> Self {
        Self { text: text.into() }
    }
}

/// Action marker for cancelling text editing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CancelTextEdit;

/// Text-edit reducer action surface.
#[derive(Clone, Debug, PartialEq)]
pub enum DrawAction {
    StartTextEdit(StartTextEdit),
    UpdateTextEdit(UpdateTextEdit),
    FinishTextEdit(FinishTextEdit),
    CancelTextEdit(CancelTextEdit),
    Other,
}

impl From<StartTextEdit> for DrawAction {
    fn from(value: StartTextEdit) -> Self {
        Self::StartTextEdit(value)
    }
}

impl From<UpdateTextEdit> for DrawAction {
    fn from(value: UpdateTextEdit) -> Self {
        Self::UpdateTextEdit(value)
    }
}

impl From<FinishTextEdit> for DrawAction {
    fn from(value: FinishTextEdit) -> Self {
        Self::FinishTextEdit(value)
    }
}

impl From<CancelTextEdit> for DrawAction {
    fn from(value: CancelTextEdit) -> Self {
        Self::CancelTextEdit(value)
    }
}

/// Context adapter consumed by [`TextEditReducer`].
pub trait TextEditReducerContext {
    fn next_id(&self) -> String;
    fn text_style(&self) -> ElementStyleConfig;

    /// Optional text metrics adapter used by text-editing geometry.
    ///
    /// While the crate migration is in progress, callers can return `None`
    /// and fall back to deterministic internal metrics.
    fn text_metrics_service(&self) -> Option<&dyn GeometryTextMetricsService> {
        None
    }
}

impl TextEditReducerContext for DrawContext {
    fn next_id(&self) -> String {
        DrawContext::next_id(self)
    }

    fn text_style(&self) -> ElementStyleConfig {
        self.config().text_style
    }

    fn text_metrics_service(&self) -> Option<&dyn GeometryTextMetricsService> {
        None
    }
}

/// State adapter consumed by [`TextEditReducer`].
pub trait TextEditReducerState: Clone {
    fn document_elements(&self) -> &[ElementState];
    fn with_document_elements(&self, elements: Vec<ElementState>) -> Self;

    fn apply_selection_change(
        &self,
        selected_ids: BTreeSet<String>,
        force_refresh_overlay: bool,
    ) -> Self;

    fn text_editing(&self) -> Option<&TextEditingState>;
    fn with_text_editing(&self, text_editing: Option<TextEditingState>) -> Self;
}

#[derive(Clone)]
struct TextEditSession {
    element_id: String,
    draft_data: TextData,
    rect: DrawRect,
    is_new: bool,
    opacity: f64,
    rotation: f64,
}

/// Reducer for text-editing interactions.
#[derive(Clone, Copy, Debug, Default)]
pub struct TextEditReducer;

impl TextEditReducer {
    pub const fn new() -> Self {
        Self
    }

    pub fn reduce<S, C>(&self, state: &S, action: &DrawAction, context: &C) -> Option<S>
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        match action {
            DrawAction::StartTextEdit(action) => Some(self.start_text_edit(state, action, context)),
            DrawAction::UpdateTextEdit(action) => {
                Some(self.update_text_edit(state, action, context))
            }
            DrawAction::FinishTextEdit(action) => {
                Some(self.finish_text_edit(state, action, context))
            }
            DrawAction::CancelTextEdit(_) => Some(self.cancel_text_edit(state)),
            DrawAction::Other => None,
        }
    }

    fn start_text_edit<S, C>(&self, state: &S, action: &StartTextEdit, context: &C) -> S
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        if state.text_editing().is_some() {
            return state.clone();
        }

        let Some(session) = self.resolve_start_session(state, action, context) else {
            return state.clone();
        };

        let mut selected_ids = BTreeSet::<String>::new();
        if !session.is_new {
            selected_ids.insert(session.element_id.clone());
        }

        let selected_state = state.apply_selection_change(selected_ids, false);
        let interaction = TextEditingState::new(
            session.element_id,
            session.draft_data,
            session.rect,
            session.is_new,
            session.opacity,
            session.rotation,
            Some(action.position),
        );

        selected_state.with_text_editing(Some(interaction))
    }

    fn resolve_start_session<S, C>(
        &self,
        state: &S,
        action: &StartTextEdit,
        context: &C,
    ) -> Option<TextEditSession>
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        match action.element_id.as_deref() {
            Some(element_id) => self.resolve_existing_session(state, element_id),
            None => Some(self.resolve_new_session(action, context)),
        }
    }

    fn resolve_existing_session<S>(&self, state: &S, element_id: &str) -> Option<TextEditSession>
    where
        S: TextEditReducerState,
    {
        let element = state
            .document_elements()
            .iter()
            .find(|element| element.id == element_id)?;
        let data = decode_text_data(element.data.as_ref())?;

        Some(TextEditSession {
            element_id: element.id.clone(),
            draft_data: data,
            rect: element.rect,
            is_new: false,
            opacity: element.opacity,
            rotation: element.rotation,
        })
    }

    fn resolve_new_session<C>(&self, action: &StartTextEdit, context: &C) -> TextEditSession
    where
        C: TextEditReducerContext,
    {
        let defaults = context.text_style();
        let draft_data = build_styled_text_data(&defaults);
        let rect = resolve_initial_text_editing_rect(
            action.position,
            &to_geometry_text_data(&draft_data),
            context.text_metrics_service(),
            None,
        );

        TextEditSession {
            element_id: context.next_id(),
            draft_data,
            rect,
            is_new: true,
            opacity: defaults.opacity,
            rotation: 0.0,
        }
    }

    fn update_text_edit<S, C>(&self, state: &S, action: &UpdateTextEdit, context: &C) -> S
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        let Some(interaction) = state.text_editing() else {
            return state.clone();
        };

        let text_unchanged = action.text == interaction.draft_data.text;
        if text_unchanged && action.rect.is_none() {
            return state.clone();
        }

        let next_data = if text_unchanged {
            interaction.draft_data.clone()
        } else {
            interaction.draft_data.copy_with(TextDataPatch {
                text: Some(action.text.clone()),
                ..TextDataPatch::default()
            })
        };

        let next_rect = action
            .rect
            .unwrap_or_else(|| self.resolve_text_draft_rect(interaction.rect, &next_data, context));
        if next_data == interaction.draft_data && next_rect == interaction.rect {
            return state.clone();
        }

        state.with_text_editing(Some(interaction.copy_with(
            Some(next_data),
            Some(next_rect),
            None,
            None,
            None,
            None,
        )))
    }

    fn finish_text_edit<S, C>(&self, state: &S, action: &FinishTextEdit, context: &C) -> S
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        let Some(interaction) = state.text_editing() else {
            return state.clone();
        };

        if action.text.trim().is_empty() {
            return self.finish_empty_text(state, interaction);
        }

        self.commit_text_draft(state, interaction, &action.text, context)
    }

    fn finish_empty_text<S>(&self, state: &S, interaction: &TextEditingState) -> S
    where
        S: TextEditReducerState,
    {
        if interaction.is_new {
            return self.to_idle(state);
        }

        self.delete_existing_text(state, interaction)
    }

    fn commit_text_draft<S, C>(
        &self,
        state: &S,
        interaction: &TextEditingState,
        raw_text: &str,
        context: &C,
    ) -> S
    where
        S: TextEditReducerState,
        C: TextEditReducerContext,
    {
        let next_data = interaction.draft_data.copy_with(TextDataPatch {
            text: Some(raw_text.to_owned()),
            ..TextDataPatch::default()
        });
        let next_rect = self.resolve_text_draft_rect(interaction.rect, &next_data, context);

        if interaction.is_new {
            return self.create_text_element(state, interaction, next_data, next_rect);
        }

        self.update_text_element(state, interaction, next_data, next_rect)
    }

    fn create_text_element<S>(
        &self,
        state: &S,
        interaction: &TextEditingState,
        data: TextData,
        rect: DrawRect,
    ) -> S
    where
        S: TextEditReducerState,
    {
        let element = ElementState::new(
            interaction.element_id.clone(),
            rect,
            0.0,
            interaction.opacity,
            resolve_next_z_index(state.document_elements().iter()),
            Arc::new(data),
        );

        let mut next_elements = state.document_elements().to_vec();
        next_elements.push(element);
        let next_state = state.with_document_elements(next_elements);

        self.finish_text_editing(&next_state)
    }

    fn update_text_element<S>(
        &self,
        state: &S,
        interaction: &TextEditingState,
        data: TextData,
        rect: DrawRect,
    ) -> S
    where
        S: TextEditReducerState,
    {
        let Some(current_element) = state
            .document_elements()
            .iter()
            .find(|element| element.id == interaction.element_id)
        else {
            return self.finish_text_editing(state);
        };

        let data_unchanged =
            decode_text_data(current_element.data.as_ref()).as_ref() == Some(&data);
        if current_element.rect == rect && data_unchanged {
            return self.finish_text_editing(state);
        }

        let mut replacements_by_id = HashMap::<String, ElementState>::new();
        replacements_by_id.insert(
            interaction.element_id.clone(),
            current_element.copy_with(None, Some(rect), None, None, None, Some(Arc::new(data))),
        );

        let next_elements = EditApply::replace_elements_by_id(
            state.document_elements().to_vec(),
            &replacements_by_id,
        );
        let next_state = state.with_document_elements(next_elements);

        self.finish_text_editing(&next_state)
    }

    fn delete_existing_text<S>(&self, state: &S, interaction: &TextEditingState) -> S
    where
        S: TextEditReducerState,
    {
        let next_state = match self.remove_text_element_and_unbind_references(
            state.document_elements(),
            &interaction.element_id,
        ) {
            Some(next_elements) => state.with_document_elements(next_elements),
            None => state.clone(),
        };

        self.finish_text_editing(&next_state)
    }

    fn remove_text_element_and_unbind_references(
        &self,
        elements: &[ElementState],
        deleted_text_id: &str,
    ) -> Option<Vec<ElementState>> {
        let mut next_elements = Vec::<ElementState>::with_capacity(elements.len());
        let mut changed = false;

        for element in elements {
            if element.id == deleted_text_id {
                changed = true;
                continue;
            }

            let updated = clear_element_dependencies_for_deleted_text_id(element, deleted_text_id);
            if updated != *element {
                changed = true;
            }
            next_elements.push(updated);
        }

        if changed {
            Some(next_elements)
        } else {
            None
        }
    }

    fn cancel_text_edit<S>(&self, state: &S) -> S
    where
        S: TextEditReducerState,
    {
        if state.text_editing().is_none() {
            return state.clone();
        }
        self.to_idle(state)
    }

    fn resolve_text_draft_rect<C>(
        &self,
        current_rect: DrawRect,
        data: &TextData,
        context: &C,
    ) -> DrawRect
    where
        C: TextEditReducerContext,
    {
        resolve_text_editing_rect(
            DrawPoint::new(current_rect.min_x, current_rect.min_y),
            current_rect,
            &to_geometry_text_data(data),
            context.text_metrics_service(),
            true,
            None,
        )
    }

    fn to_idle<S>(&self, state: &S) -> S
    where
        S: TextEditReducerState,
    {
        state.with_text_editing(None)
    }

    fn finish_text_editing<S>(&self, state: &S) -> S
    where
        S: TextEditReducerState,
    {
        let next_state = state.apply_selection_change(BTreeSet::new(), false);
        self.to_idle(&next_state)
    }
}

/// Convenience entry point matching Dart reducer style.
pub fn reduce_text_edit<S, C>(state: &S, action: &DrawAction, context: &C) -> Option<S>
where
    S: TextEditReducerState,
    C: TextEditReducerContext,
{
    TextEditReducer::new().reduce(state, action, context)
}

fn build_styled_text_data(style: &ElementStyleConfig) -> TextData {
    let styled = TextData::default().with_element_style(style.clone());
    TextData::from_json(&styled.to_json()).unwrap_or_default()
}

fn to_geometry_text_data(data: &TextData) -> GeometryTextData {
    GeometryTextData {
        text: data.text.clone(),
        font_size: data.font_size,
        auto_resize: data.auto_resize,
    }
}

fn clear_element_dependencies_for_deleted_text_id(
    element: &ElementState,
    deleted_text_id: &str,
) -> ElementState {
    if let Some(serial_data) = decode_serial_number_data(element.data.as_ref()) {
        if serial_data.text_element_id.as_deref() == Some(deleted_text_id) {
            let next_data = serial_data.copy_with(SerialNumberDataPatch {
                text_element_id: Some(None),
                ..SerialNumberDataPatch::default()
            });
            return element.copy_with(None, None, None, None, None, Some(Arc::new(next_data)));
        }
        return element.clone();
    }

    if let Some(arrow_data) = decode_arrow_data(element.data.as_ref()) {
        let clear_start = arrow_data
            .start_binding
            .as_ref()
            .is_some_and(|binding| binding.element_id == deleted_text_id);
        let clear_end = arrow_data
            .end_binding
            .as_ref()
            .is_some_and(|binding| binding.element_id == deleted_text_id);

        if clear_start || clear_end {
            let next_data = arrow_data.copy_with(ArrowDataPatch {
                start_binding: if clear_start {
                    ArrowNullableField::Null
                } else {
                    ArrowNullableField::Unset
                },
                end_binding: if clear_end {
                    ArrowNullableField::Null
                } else {
                    ArrowNullableField::Unset
                },
                start_is_special: if clear_start {
                    ArrowNullableField::Null
                } else {
                    ArrowNullableField::Unset
                },
                end_is_special: if clear_end {
                    ArrowNullableField::Null
                } else {
                    ArrowNullableField::Unset
                },
                ..ArrowDataPatch::default()
            });
            return element.copy_with(None, None, None, None, None, Some(Arc::new(next_data)));
        }
    }

    element.clone()
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

fn decode_arrow_data(data: &dyn ElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}
