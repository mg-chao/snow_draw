#![allow(dead_code)]

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use serde_json::Map;
use serde_json::Value;

use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::core::element_data::{
    DynElementData, ElementData as CoreElementData, ElementTypeId,
};
use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding as LineArrowBinding;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as ArrowDataBinding, ArrowData, ArrowDataPatch,
    NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::{
    SerialNumberData, SerialNumberDataPatch,
};
use crate::draw::elements::types::serial_number::serial_number_dependencies::SerialNumberDependencyElement;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::application_state::{
    ApplicationState, InteractionState, TextEditingState,
};
use crate::draw::models::draw_state::{DomainDocumentState, DomainState, DrawState};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::selection_state::SelectionState;
use crate::draw::reducers::core::reducer_utils::apply_selection_change;
use crate::draw::types::draw_point::DrawPoint;

use super::delete_element_handler;
use super::global_elements_handler;
use super::serial_number_handler;
use super::style_handler;
use super::text_layout_refresh_handler;
use super::zindex_handler;

pub type DeleteElements = delete_element_handler::DeleteElements;
pub type DuplicateElements = delete_element_handler::DuplicateElements;
pub type ChangeElementZIndex = zindex_handler::ChangeElementZIndex;
pub type ChangeElementsZIndex = zindex_handler::ChangeElementsZIndex;
pub type UpdateElementsStyle = style_handler::UpdateElementsStyleAction;
pub type RefreshAutoResizeTextLayoutsAfterFontLoad =
    crate::draw::actions::draw_actions::RefreshAutoResizeTextLayoutsAfterFontLoad;
pub type UpdateGlobalElements = global_elements_handler::UpdateGlobalElements;
pub type CreateSerialNumberTextElements = serial_number_handler::CreateSerialNumberTextElements;

/// Element-scoped draw actions handled by [`element_reducer`].
#[derive(Clone, Debug, PartialEq)]
pub enum ElementReducerAction {
    DeleteElements(DeleteElements),
    DuplicateElements(DuplicateElements),
    ChangeElementZIndex(ChangeElementZIndex),
    ChangeElementsZIndex(ChangeElementsZIndex),
    UpdateElementsStyle(UpdateElementsStyle),
    RefreshAutoResizeTextLayoutsAfterFontLoad(RefreshAutoResizeTextLayoutsAfterFontLoad),
    UpdateGlobalElements(UpdateGlobalElements),
    CreateSerialNumberTextElements(CreateSerialNumberTextElements),
    Other,
}

impl Default for ElementReducerAction {
    fn default() -> Self {
        Self::Other
    }
}

/// Element reducer translated from Dart `elementReducer`.
///
/// Returns `Some(next_state)` for handled actions and `None` for unknown
/// actions.
pub fn element_reducer(
    state: DrawState,
    action: &ElementReducerAction,
    context: &DrawContext,
) -> Option<DrawState> {
    match action {
        ElementReducerAction::DeleteElements(action) => Some(
            delete_element_handler::handle_delete_elements(&state, action, context),
        ),
        ElementReducerAction::DuplicateElements(action) => Some(
            delete_element_handler::handle_duplicate_elements(&state, action, context),
        ),
        ElementReducerAction::ChangeElementZIndex(action) => Some(
            zindex_handler::handle_change_z_index(&state, action, context),
        ),
        ElementReducerAction::ChangeElementsZIndex(action) => Some(
            zindex_handler::handle_change_z_index_batch(&state, action, context),
        ),
        ElementReducerAction::UpdateElementsStyle(action) => Some(
            style_handler::handle_update_elements_style(&state, action, context),
        ),
        ElementReducerAction::RefreshAutoResizeTextLayoutsAfterFontLoad(action) => {
            text_layout_refresh_handler::handle_refresh_auto_resize_text_layouts_after_font_load(
                state, action, context,
            )
        }
        ElementReducerAction::UpdateGlobalElements(action) => Some(
            global_elements_handler::handle_update_global_elements(&state, action, context),
        ),
        ElementReducerAction::CreateSerialNumberTextElements(action) => Some(
            serial_number_handler::handle_create_serial_number_text_elements(
                &state, action, context,
            ),
        ),
        ElementReducerAction::Other => None,
    }
}

impl SerialNumberDependencyElement for ElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn is_serial_number_element(&self) -> bool {
        self.data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN
    }

    fn serial_number_text_element_id(&self) -> Option<String> {
        let data = decode_serial_number_data(self.data.as_ref())?;
        data.text_element_id
    }

    fn with_serial_number_text_element_id(&self, text_element_id: Option<String>) -> Self {
        let Some(data) = decode_serial_number_data(self.data.as_ref()) else {
            return self.clone();
        };

        let next_data = data.copy_with(SerialNumberDataPatch {
            text_element_id: Some(text_element_id),
            ..SerialNumberDataPatch::default()
        });

        self.copy_with(None, None, None, None, None, Some(Arc::new(next_data)))
    }

    fn is_arrow_like_element(&self) -> bool {
        matches!(
            self.data.type_id().as_str(),
            ArrowData::TYPE_ID_TOKEN | LineData::TYPE_ID_TOKEN
        )
    }

    fn arrow_start_binding_element_id(&self) -> Option<String> {
        if let Some(data) = decode_arrow_data(self.data.as_ref()) {
            return data
                .start_binding
                .as_ref()
                .map(|binding| binding.element_id.clone());
        }
        if let Some(data) = decode_line_data(self.data.as_ref()) {
            return data
                .start_binding
                .as_ref()
                .map(|binding| binding.element_id.clone());
        }
        None
    }

    fn arrow_end_binding_element_id(&self) -> Option<String> {
        if let Some(data) = decode_arrow_data(self.data.as_ref()) {
            return data
                .end_binding
                .as_ref()
                .map(|binding| binding.element_id.clone());
        }
        if let Some(data) = decode_line_data(self.data.as_ref()) {
            return data
                .end_binding
                .as_ref()
                .map(|binding| binding.element_id.clone());
        }
        None
    }

    fn with_cleared_arrow_bindings(&self, clear_start: bool, clear_end: bool) -> Self {
        if let Some(data) = decode_arrow_data(self.data.as_ref()) {
            let next_data = data.copy_with(ArrowDataPatch {
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
            return self.copy_with(None, None, None, None, None, Some(Arc::new(next_data)));
        }

        if let Some(data) = decode_line_data(self.data.as_ref()) {
            let next_data = data.copy_with(LineDataPatch {
                start_binding: if clear_start {
                    ArrowLikeNullableField::Null
                } else {
                    ArrowLikeNullableField::Unset
                },
                end_binding: if clear_end {
                    ArrowLikeNullableField::Null
                } else {
                    ArrowLikeNullableField::Unset
                },
                start_is_special: if clear_start {
                    ArrowLikeNullableField::Null
                } else {
                    ArrowLikeNullableField::Unset
                },
                end_is_special: if clear_end {
                    ArrowLikeNullableField::Null
                } else {
                    ArrowLikeNullableField::Unset
                },
                ..LineDataPatch::default()
            });
            return self.copy_with(None, None, None, None, None, Some(Arc::new(next_data)));
        }

        self.clone()
    }
}

impl delete_element_handler::ElementReducerElement for ElementState {
    fn z_index(&self) -> i64 {
        self.z_index
    }

    fn duplicate_with_remapped_references(
        &self,
        new_id: String,
        offset_x: f64,
        offset_y: f64,
        z_index: i64,
        id_map: &HashMap<String, String>,
    ) -> Self {
        self.copy_with(
            Some(new_id),
            Some(self.rect.translate(DrawPoint::new(offset_x, offset_y))),
            None,
            None,
            Some(z_index),
            Some(duplicate_data_with_remapped_references(
                self.data.as_ref(),
                id_map,
            )),
        )
    }
}

impl delete_element_handler::ElementReducerState for DrawState {
    type Element = ElementState;

    fn elements(&self) -> &[Self::Element] {
        &self.domain.document.elements
    }

    fn selected_ids(&self) -> &BTreeSet<String> {
        &self.domain.selection.selected_ids
    }

    fn with_elements_and_selection(
        &self,
        elements: Vec<Self::Element>,
        selected_ids: BTreeSet<String>,
    ) -> Self {
        let document = self.domain.document.copy_with(Some(elements), None, None);
        let domain = self.domain.copy_with(Some(document), None);
        let next = self.copy_with(Some(domain), None);
        apply_selection_change(&next, selected_ids, false)
    }
}

impl zindex_handler::ZIndexReducerDocument for DomainDocumentState {
    type Element = ElementState;

    fn elements(&self) -> &[Self::Element] {
        &self.elements
    }

    fn with_elements(&self, elements: Vec<Self::Element>) -> Self {
        self.copy_with(Some(elements), None, None)
    }
}

impl zindex_handler::ZIndexReducerDomain for DomainState {
    type Document = DomainDocumentState;

    fn document(&self) -> &Self::Document {
        &self.document
    }

    fn with_document(&self, document: Self::Document) -> Self {
        self.copy_with(Some(document), None)
    }
}

impl zindex_handler::ZIndexReducerState for DrawState {
    type Domain = DomainState;

    fn domain(&self) -> &Self::Domain {
        &self.domain
    }

    fn with_domain(&self, domain: Self::Domain) -> Self {
        self.copy_with(Some(domain), None)
    }
}

impl style_handler::StyleReducerSelection for SelectionState {
    fn selected_ids(&self) -> &BTreeSet<String> {
        &self.selected_ids
    }
}

impl style_handler::StyleReducerDocument for DomainDocumentState {
    fn elements(&self) -> &[ElementState] {
        &self.elements
    }

    fn with_elements(&self, elements: Vec<ElementState>) -> Self {
        self.copy_with(Some(elements), None, None)
    }
}

impl style_handler::StyleReducerDomain for DomainState {
    type Document = DomainDocumentState;
    type Selection = SelectionState;

    fn document(&self) -> &Self::Document {
        &self.document
    }

    fn selection(&self) -> &Self::Selection {
        &self.selection
    }

    fn with_document(&self, document: Self::Document) -> Self {
        self.copy_with(Some(document), None)
    }
}

impl style_handler::StyleReducerInteraction for InteractionState {
    fn as_text_editing(&self) -> Option<&TextEditingState> {
        let InteractionState::TextEditing(text_editing) = self else {
            return None;
        };
        Some(text_editing)
    }

    fn from_text_editing(text_editing: TextEditingState) -> Self {
        InteractionState::TextEditing(text_editing)
    }
}

impl style_handler::StyleReducerApplication for ApplicationState {
    type Interaction = InteractionState;

    fn interaction(&self) -> &Self::Interaction {
        &self.interaction
    }

    fn with_interaction(&self, interaction: Self::Interaction) -> Self {
        self.copy_with(None, Some(interaction), None)
    }
}

impl style_handler::StyleReducerState for DrawState {
    type Domain = DomainState;
    type Application = ApplicationState;

    fn domain(&self) -> &Self::Domain {
        &self.domain
    }

    fn application(&self) -> &Self::Application {
        &self.application
    }

    fn with_domain(&self, domain: Self::Domain) -> Self {
        self.copy_with(Some(domain), None)
    }

    fn with_application(&self, application: Self::Application) -> Self {
        self.copy_with(None, Some(application))
    }

    fn apply_selection_change(
        &self,
        selected_ids: BTreeSet<String>,
        force_refresh_overlay: bool,
    ) -> Self {
        apply_selection_change(self, selected_ids, force_refresh_overlay)
    }
}

impl global_elements_handler::GlobalElementsReducerDocument for DomainDocumentState {
    fn global_elements(&self) -> &crate::draw::models::global_elements_state::GlobalElementsState {
        &self.global_elements
    }

    fn with_global_elements(
        &self,
        global_elements: crate::draw::models::global_elements_state::GlobalElementsState,
    ) -> Self {
        self.copy_with(None, Some(global_elements), None)
    }
}

impl global_elements_handler::GlobalElementsReducerDomain for DomainState {
    type Document = DomainDocumentState;

    fn document(&self) -> &Self::Document {
        &self.document
    }

    fn with_document(&self, document: Self::Document) -> Self {
        self.copy_with(Some(document), None)
    }
}

impl global_elements_handler::GlobalElementsReducerState for DrawState {
    type Domain = DomainState;

    fn domain(&self) -> &Self::Domain {
        &self.domain
    }

    fn with_domain(&self, domain: Self::Domain) -> Self {
        self.copy_with(Some(domain), None)
    }
}

impl serial_number_handler::SerialNumberTextReducerState for DrawState {
    fn document_elements(&self) -> &[ElementState] {
        &self.domain.document.elements
    }

    fn with_document_elements(&self, elements: Vec<ElementState>) -> Self {
        let document = self.domain.document.copy_with(Some(elements), None, None);
        let domain = self.domain.copy_with(Some(document), None);
        self.copy_with(Some(domain), None)
    }

    fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self {
        apply_selection_change(self, selected_ids, false)
    }

    fn with_interaction(&self, interaction: InteractionState) -> Self {
        let application = self.application.copy_with(None, Some(interaction), None);
        self.copy_with(None, Some(application))
    }
}

#[derive(Clone, Debug, PartialEq)]
struct RawJsonElementData {
    type_id: ElementTypeId<DynElementData>,
    json: Map<String, Value>,
}

impl RawJsonElementData {
    fn from_data(data: &dyn CoreElementData) -> Self {
        Self {
            type_id: data.type_id(),
            json: data.to_json(),
        }
    }
}

impl CoreElementData for RawJsonElementData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        self.type_id.clone()
    }

    fn to_json(&self) -> Map<String, Value> {
        self.json.clone()
    }
}

fn duplicate_data_with_remapped_references(
    data: &dyn CoreElementData,
    id_map: &HashMap<String, String>,
) -> Arc<dyn CoreElementData> {
    if let Some(serial_data) = decode_serial_number_data(data) {
        let next_data = serial_data.copy_with(SerialNumberDataPatch {
            text_element_id: Some(
                serial_data
                    .text_element_id
                    .as_ref()
                    .and_then(|id| id_map.get(id).cloned()),
            ),
            ..SerialNumberDataPatch::default()
        });
        return Arc::new(next_data);
    }

    if let Some(arrow_data) = decode_arrow_data(data) {
        return Arc::new(remap_arrow_data_bindings(&arrow_data, id_map));
    }

    if let Some(line_data) = decode_line_data(data) {
        return Arc::new(remap_line_data_bindings(&line_data, id_map));
    }

    clone_core_element_data(data)
}

fn remap_arrow_data_bindings(data: &ArrowData, id_map: &HashMap<String, String>) -> ArrowData {
    let start_binding = remap_arrow_data_binding(data.start_binding.as_ref(), id_map);
    let end_binding = remap_arrow_data_binding(data.end_binding.as_ref(), id_map);
    let clear_start_special = data.start_binding.is_some() && start_binding.is_none();
    let clear_end_special = data.end_binding.is_some() && end_binding.is_none();

    data.copy_with(ArrowDataPatch {
        start_binding: map_arrow_nullable_binding(start_binding),
        end_binding: map_arrow_nullable_binding(end_binding),
        start_is_special: if clear_start_special {
            ArrowNullableField::Null
        } else {
            ArrowNullableField::Unset
        },
        end_is_special: if clear_end_special {
            ArrowNullableField::Null
        } else {
            ArrowNullableField::Unset
        },
        ..ArrowDataPatch::default()
    })
}

fn remap_line_data_bindings(data: &LineData, id_map: &HashMap<String, String>) -> LineData {
    let start_binding = remap_line_binding(data.start_binding.as_ref(), id_map);
    let end_binding = remap_line_binding(data.end_binding.as_ref(), id_map);
    let clear_start_special = data.start_binding.is_some() && start_binding.is_none();
    let clear_end_special = data.end_binding.is_some() && end_binding.is_none();

    data.copy_with(LineDataPatch {
        start_binding: map_arrow_like_nullable_binding(start_binding),
        end_binding: map_arrow_like_nullable_binding(end_binding),
        start_is_special: if clear_start_special {
            ArrowLikeNullableField::Null
        } else {
            ArrowLikeNullableField::Unset
        },
        end_is_special: if clear_end_special {
            ArrowLikeNullableField::Null
        } else {
            ArrowLikeNullableField::Unset
        },
        ..LineDataPatch::default()
    })
}

fn remap_arrow_data_binding(
    binding: Option<&ArrowDataBinding>,
    id_map: &HashMap<String, String>,
) -> Option<ArrowDataBinding> {
    let binding = binding?;
    let target_id = id_map.get(binding.element_id.as_str())?;
    Some(ArrowDataBinding::new(
        target_id.clone(),
        binding.anchor,
        binding.mode,
    ))
}

fn remap_line_binding(
    binding: Option<&LineArrowBinding>,
    id_map: &HashMap<String, String>,
) -> Option<LineArrowBinding> {
    let binding = binding?;
    let target_id = id_map.get(binding.element_id.as_str())?;
    Some(binding.copy_with(Some(target_id.clone()), None, None))
}

fn map_arrow_nullable_binding(
    binding: Option<ArrowDataBinding>,
) -> ArrowNullableField<ArrowDataBinding> {
    match binding {
        Some(binding) => ArrowNullableField::Value(binding),
        None => ArrowNullableField::Null,
    }
}

fn map_arrow_like_nullable_binding(
    binding: Option<LineArrowBinding>,
) -> ArrowLikeNullableField<LineArrowBinding> {
    match binding {
        Some(binding) => ArrowLikeNullableField::Value(binding),
        None => ArrowLikeNullableField::Null,
    }
}

fn clone_core_element_data(data: &dyn CoreElementData) -> Arc<dyn CoreElementData> {
    if let Some(decoded) = decode_rectangle_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_arrow_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_line_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_free_draw_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_highlight_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_filter_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_text_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_serial_number_data(data) {
        return Arc::new(decoded);
    }

    Arc::new(RawJsonElementData::from_data(data))
}

fn decode_rectangle_data(data: &dyn CoreElementData) -> Option<RectangleData> {
    if data.type_id().as_str() != RectangleData::TYPE_ID_TOKEN {
        return None;
    }
    RectangleData::from_json(&data.to_json()).ok()
}

fn decode_arrow_data(data: &dyn CoreElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}

fn decode_line_data(data: &dyn CoreElementData) -> Option<LineData> {
    if data.type_id().as_str() != LineData::TYPE_ID_TOKEN {
        return None;
    }
    LineData::from_json(&data.to_json()).ok()
}

fn decode_free_draw_data(data: &dyn CoreElementData) -> Option<FreeDrawData> {
    if data.type_id().as_str() != FreeDrawData::TYPE_ID_TOKEN {
        return None;
    }
    FreeDrawData::from_json(&data.to_json()).ok()
}

fn decode_highlight_data(data: &dyn CoreElementData) -> Option<HighlightData> {
    if data.type_id().as_str() != HighlightData::TYPE_ID_TOKEN {
        return None;
    }
    HighlightData::from_json(&data.to_json()).ok()
}

fn decode_filter_data(data: &dyn CoreElementData) -> Option<FilterData> {
    if data.type_id().as_str() != FilterData::TYPE_ID_TOKEN {
        return None;
    }
    FilterData::from_json(&data.to_json()).ok()
}

fn decode_text_data(data: &dyn CoreElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn CoreElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::element_style::ElementStyleUpdate;

    #[test]
    fn unknown_action_returns_none() {
        let state = DrawState::default();
        let context = DrawContext::default();

        assert!(element_reducer(state, &ElementReducerAction::Other, &context).is_none());
    }

    #[test]
    fn style_action_is_dispatched() {
        let state = DrawState::default();
        let context = DrawContext::default();
        let action = ElementReducerAction::UpdateElementsStyle(UpdateElementsStyle {
            element_ids: vec!["missing".to_owned()],
            style_update: ElementStyleUpdate::default(),
            opacity: Some(0.5),
        });

        let next = element_reducer(state.clone(), &action, &context);
        assert!(next.is_some());
    }
}
